/* Copyright 2017 The TensorFlow Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
==============================================================================*/

#include "tao_bridge/tf/const_analysis.h"

#include <unordered_map>
#include <unordered_set>

#include "tao_bridge/tf/xla_op_registry.h"
#include "tao_bridge/errors.h"
#include "tensorflow/core/common_runtime/function.h"
#include "tensorflow/core/framework/attr_value.pb.h"
#include "tensorflow/core/framework/function.h"
#include "tensorflow/core/framework/node_def_util.h"
#include "tensorflow/core/graph/algorithm.h"
#include "tensorflow/core/lib/core/errors.h"

namespace tensorflow {
namespace tao {

namespace {

Status GetFunctionBody(FunctionLibraryRuntime* flib_runtime,
                       const NodeDef& node, StringPiece func_attr_name,
                       const FunctionBody** fbody) {
  NameAttrList name_attr_list;
  TF_RETURN_IF_ERROR(GetNodeAttr(node, func_attr_name, &name_attr_list));
  FunctionLibraryRuntime::Handle func_handle;
  TF_RETURN_IF_ERROR(flib_runtime->Instantiate(
      name_attr_list.name(), AttrSlice(&name_attr_list.attr()), &func_handle));
  *fbody = flib_runtime->GetFunctionBody(func_handle);
  return Status::OK();
}

Status GetFunctionBodies(FunctionLibraryRuntime* flib_runtime,
                         const NodeDef& node, StringPiece func_list_attr_name,
                         std::vector<const FunctionBody*>* fbodies) {
  std::vector<NameAttrList> name_attr_lists;
  TF_RETURN_IF_ERROR(GetNodeAttr(node, func_list_attr_name, &name_attr_lists));
  for (const NameAttrList& name_attr_list : name_attr_lists) {
    FunctionLibraryRuntime::Handle func_handle;
    TF_RETURN_IF_ERROR(flib_runtime->Instantiate(
        name_attr_list.name(), AttrSlice(&name_attr_list.attr()),
        &func_handle));
    fbodies->push_back(flib_runtime->GetFunctionBody(func_handle));
  }
  return Status::OK();
}

Status CondConstInputIndices(
    absl::Span<const FunctionBody* const> branch_bodies,
    std::vector<int>* const_input_idxs,
    std::vector<int>* fixed_shape_input_idxs,
    FunctionLibraryRuntime* flib_runtime, bool is_mlir = false) {
  TF_RET_CHECK(!branch_bodies.empty());
  TF_RET_CHECK(branch_bodies[0] != nullptr);
  int num_inputs = branch_bodies[0]->fdef.signature().input_arg_size();
  // Stores indices of the "branch function" inputs that are expected to be
  // compile time constants.
  std::vector<bool> compile_time_const_arg_indices(num_inputs);
  std::vector<bool> compile_time_fixed_shape_arg_indices(num_inputs);
  for (auto fbody : branch_bodies) {
    TF_RET_CHECK(fbody != nullptr);
    TF_RETURN_IF_ERROR(BackwardsConstAnalysis(
        *(fbody->graph), &compile_time_const_arg_indices,
        /*compile_time_const_nodes=*/nullptr,
        &compile_time_fixed_shape_arg_indices,
        /*compile_time_fixed_shape_nodes=*/nullptr, flib_runtime,
        /*edge_filter*/ [](const Edge& e) { return true; }, is_mlir));
  }
  for (size_t i = 0; i < compile_time_const_arg_indices.size(); i++) {
    if (compile_time_const_arg_indices[i]) {
      // The 0th input is the pred or branch index, which is not passed to the
      // branches. So the i'th input of a branch function corresponds to the
      // i + 1'th input of the If/Case op.
      const_input_idxs->push_back(i + 1);
    }
    if (compile_time_fixed_shape_arg_indices[i]) {
      // The 0th input is the pred or branch index, which is not passed to the
      // branches. So the i'th input of a branch function corresponds to the
      // i + 1'th input of the If/Case op.
      fixed_shape_input_idxs->push_back(i + 1);
    }
  }
  return Status::OK();
}

Status GetCompileTimeConstInputs(const NodeDef& node, const OpKernel* op_kernel,
                                 const OpDef* op_def,
                                 std::vector<int>* const_input_idxs,
                                 std::vector<int>* fixed_shape_input_idxs,
                                 FunctionLibraryRuntime* flib_runtime,
                                 bool is_mlir = false) {
  DCHECK(op_def != nullptr || op_kernel != nullptr);
  // TODO(b/124403063): Implement similar functionality for function call nodes.
  if (node.op() == "While" || node.op() == "StatelessWhile") {
    // For While nodes, recurse into the body and cond graphs.
    const FunctionBody* fcond = nullptr;
    const FunctionBody* fbody = nullptr;
    TF_RETURN_IF_ERROR(GetFunctionBody(flib_runtime, node, "cond", &fcond));
    TF_RETURN_IF_ERROR(GetFunctionBody(flib_runtime, node, "body", &fbody));
    TF_RET_CHECK(fcond);
    TF_RET_CHECK(fbody);
    int num_inputs = fbody->fdef.signature().input_arg_size();

    // Stores which of the loop inputs are expected to be compile time
    // constants.
    std::vector<bool> compile_time_const_arg_indices(num_inputs);
    std::vector<bool> compile_time_fixed_shape_arg_indices(num_inputs);
    TF_RETURN_IF_ERROR(BackwardsConstAnalysis(
        *(fcond->graph), &compile_time_const_arg_indices,
        /*compile_time_const_nodes=*/nullptr,
        &compile_time_fixed_shape_arg_indices,
        /*compile_time_fixed_shape_nodes=*/nullptr, flib_runtime,
        /*edge_filter*/ [](const Edge& e) { return true; }, is_mlir));
    TF_RETURN_IF_ERROR(BackwardsConstAnalysis(
        *(fbody->graph), &compile_time_const_arg_indices,
        /*compile_time_const_nodes=*/nullptr,
        &compile_time_fixed_shape_arg_indices,
        /*compile_time_fixed_shape_nodes=*/nullptr, flib_runtime,
        /*edge_filter*/ [](const Edge& e) { return true; }, is_mlir));
    for (int i = 0; i < num_inputs; i++) {
      if (compile_time_const_arg_indices[i]) {
        // Check that this input is actually a loop invariant.
        // NOTE(srbs): Ideally this should raise an error if the loop body
        // requires the input at this index to be a compile time const but it is
        // not a loop invariant. However, that causes problems because const
        // analysis is performed for the entire graph (in the
        // MarkForCompilationPass for example) and not just for the ops
        // that will actually be run using XLA kernels. So we silently return
        // here and let the error be raised during the actual compilation of the
        // XLA graph.
        Node* arg_i = fbody->arg_nodes[i];
        Node* ret_i = fbody->ret_nodes[i];
        const Node* ret_i_input_0;
        TF_RETURN_IF_ERROR(ret_i->input_node(0, &ret_i_input_0));
        if (ret_i_input_0->id() == arg_i->id()) {
          const_input_idxs->push_back(i);
        }
      }
      if (compile_time_fixed_shape_arg_indices[i]) {
        Node* arg_i = fbody->arg_nodes[i];
        Node* ret_i = fbody->ret_nodes[i];
        const Node* ret_i_input_0;
        TF_RETURN_IF_ERROR(ret_i->input_node(0, &ret_i_input_0));
        if (ret_i_input_0->id() == arg_i->id()) {
          fixed_shape_input_idxs->push_back(i);
        }
      }
    }
    return Status::OK();
  } else if (node.op() == "If" || node.op() == "StatelessIf") {
    const FunctionBody* fthen = nullptr;
    const FunctionBody* felse = nullptr;
    TF_RETURN_IF_ERROR(
        GetFunctionBody(flib_runtime, node, "then_branch", &fthen));
    TF_RETURN_IF_ERROR(
        GetFunctionBody(flib_runtime, node, "else_branch", &felse));
    return CondConstInputIndices({fthen, felse}, const_input_idxs,
                                 fixed_shape_input_idxs, flib_runtime, is_mlir);
  } else if (node.op() == "Case") {
    std::vector<const FunctionBody*> branch_bodies;
    TF_RETURN_IF_ERROR(
        GetFunctionBodies(flib_runtime, node, "branches", &branch_bodies));
    return CondConstInputIndices(branch_bodies, const_input_idxs,
                                 fixed_shape_input_idxs, flib_runtime, is_mlir);
  } else if (op_def != nullptr) {
    if (is_mlir) {
      TF_RETURN_IF_ERROR(XlaOpRegistry::CompileTimeConstantInputs(
          node, *op_def, const_input_idxs,
          XlaOpRegistry::CompileTimeConstType::kMlirCompileTimeConstantInput));
      return XlaOpRegistry::CompileTimeConstantInputs(
          node, *op_def, fixed_shape_input_idxs,
          XlaOpRegistry::CompileTimeConstType::kMlirCompileTimeFixedShapeInput);
    } else {
      return XlaOpRegistry::CompileTimeConstantInputs(
          node, *op_def, const_input_idxs,
          XlaOpRegistry::CompileTimeConstType::kXlaCompileTimeConstantInput);
    }
  } else {
    if (is_mlir) {
      TF_RETURN_IF_ERROR(XlaOpRegistry::CompileTimeConstantInputs(
          *op_kernel, const_input_idxs,
          XlaOpRegistry::CompileTimeConstType::kMlirCompileTimeConstantInput));
      return XlaOpRegistry::CompileTimeConstantInputs(
          *op_kernel, fixed_shape_input_idxs,
          XlaOpRegistry::CompileTimeConstType::kMlirCompileTimeFixedShapeInput);
    } else {
      return XlaOpRegistry::CompileTimeConstantInputs(
          *op_kernel, const_input_idxs,
          XlaOpRegistry::CompileTimeConstType::kXlaCompileTimeConstantInput);
    }
  }
}

Status GetCompileTimeConstInputs(const Node* node,
                                 std::vector<int>* const_input_idxs,
                                 std::vector<int>* fixed_shape_input_idxs,
                                 FunctionLibraryRuntime* flib_runtime,
                                 bool is_mlir = false) {
  return GetCompileTimeConstInputs(
      node->def(), /*op_kernel=*/nullptr, &node->op_def(), const_input_idxs,
      fixed_shape_input_idxs, flib_runtime, is_mlir);
}

}  // namespace

// Backwards dataflow analysis that finds arguments to a graph that must be
// compile-time constants.
Status BackwardsConstAnalysis(
    const Graph& g, std::vector<bool>* compile_time_const_arg_indices,
    std::vector<bool>* compile_time_const_nodes,
    std::vector<bool>* compile_time_fixed_shape_arg_indices,
    std::vector<bool>* compile_time_fixed_shape_nodes,
    FunctionLibraryRuntime* flib_runtime,
    std::function<bool(const Edge&)> edge_filter, bool analysis_mlir) {
  std::vector<bool> compile_time_const_nodes_impl;
  if (compile_time_const_nodes) {
    CHECK_EQ(compile_time_const_nodes->size(), g.num_node_ids());
  } else {
    compile_time_const_nodes_impl.resize(g.num_node_ids());
    compile_time_const_nodes = &compile_time_const_nodes_impl;
  }
  std::vector<bool> compile_time_fixed_shape_nodes_impl;
  if (compile_time_fixed_shape_nodes) {
    CHECK_EQ(compile_time_fixed_shape_nodes->size(), g.num_node_ids());
  } else {
    compile_time_fixed_shape_nodes_impl.resize(g.num_node_ids());
    compile_time_fixed_shape_nodes = &compile_time_fixed_shape_nodes_impl;
  }

  Status status;

  // If this node must be const, and it isn't a metadata op, then all of its
  // parents must be const.
  auto process_if_must_be_const = [&](std::vector<bool>* const_nodes,
                                      Node* node) -> bool {
    if ((*const_nodes)[node->id()]) {
      if (node->type_string() == "_Arg") {
        int index;
        status = GetNodeAttr(node->attrs(), "index", &index);
        if (!status.ok()) return true;
        if (compile_time_const_arg_indices) {
          (*compile_time_const_arg_indices)[index] = true;
        }
      } else {
        for (const Edge* pred : node->in_edges()) {
          if (!pred->IsControlEdge() && edge_filter(*pred)) {
            // If the src node of the `pred` is an IdentityN do not mark it as a
            // compile-time const. Only mark the corresponding input to the
            // IdentityN node as a const.
            // Note: XLA IdentityN op simply forwards its inputs so this is
            // safe.
            while (edge_filter(*pred) &&
                   pred->src()->type_string() == "IdentityN") {
              status = pred->src()->input_edge(pred->src_output(), &pred);
              if (!status.ok()) return true;
            }
            if (edge_filter(*pred)) {
              (*const_nodes)[pred->src()->id()] = true;
            }
          }
        }
      }
      return true;
    }
    return false;
  };

  auto visit_xla = [&](Node* node) {
    if (!status.ok()) return;

    // If this is a metadata-only op, don't propagate the const requirement.
    if (XlaOpRegistry::IsMetadataOp(node->type_string())) {
      return;
    }

    if (process_if_must_be_const(compile_time_const_nodes, node)) {
      return;
    }

    // Mark any compile-time constant operator arguments as const.
    std::vector<int> const_input_idxs;
    status = GetCompileTimeConstInputs(node, &const_input_idxs,
                                       /*fixed_shape_input_idxs*/ nullptr,
                                       flib_runtime);

    if (!status.ok()) {
      return;
    }

    for (Edge const* edge : node->in_edges()) {
      if (!edge->IsControlEdge() &&
          std::binary_search(const_input_idxs.begin(),
            const_input_idxs.end(), edge->dst_input()) &&
          edge_filter(*edge)) {
        // Do not mark IdentityN nodes as compile-time const.
        // If the src node of the `pred` is an IdentityN do not mark it as a
        // compile-time const. Only mark the corresponding input to the
        // IdentityN node as a const.
        // Note: XLA IdentityN op simply forwards its inputs so this is safe.
        while (edge_filter(*edge) &&
               edge->src()->type_string() == "IdentityN") {
          status = edge->src()->input_edge(edge->src_output(), &edge);
          if (!status.ok()) return;
        }
        if (edge_filter(*edge)) {
          (*compile_time_const_nodes)[edge->src()->id()] = true;
        }
      }
    }
  };

  auto visit_mlir = [&](Node* node) {
    if (!status.ok()) {
      return;
    }

    // If this is a metadata-only op, don't propagate the const requirement.
    if (XlaOpRegistry::IsMetadataOp(node->type_string())) {
      return;
    }

    // color all the input nodes of a must_be_const node into must_be_const
    if (process_if_must_be_const(compile_time_const_nodes, node)) {
      return;
    }

    // Mark any compile-time constant operator arguments as const.
    std::vector<int> const_input_idxs;
    std::vector<int> fixed_shape_input_idxs;
    status = GetCompileTimeConstInputs(node, &const_input_idxs,
                                       &fixed_shape_input_idxs, flib_runtime,
                                       /*is_mlir*/ true);

    if (!status.ok()) {
      return;
    }

    if ((*compile_time_fixed_shape_nodes)[node->id()] &&
        (node->type_string() == "_Arg")) {
      int index;
      status = GetNodeAttr(node->attrs(), "index", &index);
      if (!status.ok()) {
        return;
      }
      if (compile_time_fixed_shape_arg_indices) {
        (*compile_time_fixed_shape_arg_indices)[index] = true;
      }
    }

    for (Edge const* edge : node->in_edges()) {
      if (!edge->IsControlEdge() && edge_filter(*edge)) {
        if (std::binary_search(const_input_idxs.begin(), const_input_idxs.end(),
                               edge->dst_input())) {
          while (edge_filter(*edge) &&
                 edge->src()->type_string() == "IdentityN") {
            status = edge->src()->input_edge(edge->src_output(), &edge);
            if (!status.ok()) return;
          }
          if (edge_filter(*edge)) {
            (*compile_time_const_nodes)[edge->src()->id()] = true;
          }
        } else if (std::binary_search(fixed_shape_input_idxs.begin(),
                                      fixed_shape_input_idxs.end(),
                                      edge->dst_input())) {
          while (edge_filter(*edge) &&
                 edge->src()->type_string() == "IdentityN") {
            status = edge->src()->input_edge(edge->src_output(), &edge);
            if (!status.ok()) return;
          }
          if (edge_filter(*edge)) {
            if ((*compile_time_fixed_shape_nodes)[node->id()] ||
                (*compile_time_const_nodes)[node->id()]) {
              (*compile_time_const_nodes)[edge->src()->id()] = true;
            } else {
              (*compile_time_fixed_shape_nodes)[edge->src()->id()] = true;
            }
          }
        } else {
          while (edge_filter(*edge) &&
                 edge->src()->type_string() == "IdentityN") {
            status = edge->src()->input_edge(edge->src_output(), &edge);
            if (!status.ok()) return;
          }
          if (edge_filter(*edge) &&
              (*compile_time_fixed_shape_nodes)[node->id()]) {
            (*compile_time_fixed_shape_nodes)[edge->src()->id()] = true;
          }
        }
      }
    }
  };

  // Post-order traversal visits nodes in reverse topological order for an
  // acyclic graph.
  if (analysis_mlir) {
    DFS(g, /*enter=*/{}, /*leave=*/visit_mlir, NodeComparatorName{},
        [](const Edge& edge) { return !edge.src()->IsNextIteration(); });
  } else {
    DFS(g, /*enter=*/{}, /*leave=*/visit_xla, NodeComparatorName{},
        [](const Edge& edge) { return !edge.src()->IsNextIteration(); });
  }
  return status;
}

Status GetCompileTimeConstInputs(const OpKernel* op_kernel,
                                 std::vector<int>* const_input_idxs,
                                 std::vector<int>* fixed_shape_input_idxs,
                                 FunctionLibraryRuntime* flib_runtime,
                                 bool is_mlir) {
  return GetCompileTimeConstInputs(op_kernel->def(), op_kernel,
                                   /*op_def=*/nullptr, const_input_idxs,
                                   fixed_shape_input_idxs, flib_runtime,
                                   is_mlir);
}

}  // namespace tao
}  // namespace tensorflow
