// RUN: disc-opt %s -disc-lhlo-legalize-roots-to-parallel-loops -split-input-file | FileCheck %s

// CHECK-LABEL: @non_fusion_elemwise_gpu
// CHECK-SAME: (%[[INPUT1:.*]]: memref<?x?x?xf32, "gpu">, %[[INPUT2:.*]]: memref<?x?x?xf32, "gpu">, %[[OUT:.*]]: memref<?x?x?xf32, "gpu">) -> memref<?x?x?xf32, "gpu">
func @non_fusion_elemwise_gpu(%input1: memref<?x?x?xf32, "gpu">, %input2: memref<?x?x?xf32, "gpu">, %out: memref<?x?x?xf32, "gpu">) -> (memref<?x?x?xf32, "gpu">) {
  // CHECK-NOT: lmhlo
  // CHECK: scf.parallel
  "lmhlo.add"(%input1, %input2, %out) : (memref<?x?x?xf32, "gpu">, memref<?x?x?xf32, "gpu">, memref<?x?x?xf32, "gpu">) -> ()
  // CHECK: return %[[OUT]] : memref<?x?x?xf32, "gpu">
  return %out : memref<?x?x?xf32, "gpu">
}

// CHECK-LABEL: @non_fusion_elemwise_cpu
// CHECK-SAME: (%[[INPUT1:.*]]: memref<?x?x?xf32>, %[[INPUT2:.*]]: memref<?x?x?xf32>, %[[OUT:.*]]: memref<?x?x?xf32>) -> memref<?x?x?xf32>
func @non_fusion_elemwise_cpu(%input1: memref<?x?x?xf32>, %input2: memref<?x?x?xf32>, %out: memref<?x?x?xf32>) -> (memref<?x?x?xf32>) {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.add"(%input1, %input2, %out) : (memref<?x?x?xf32>, memref<?x?x?xf32>, memref<?x?x?xf32>) -> ()
  // CHECK: return %[[OUT]] : memref<?x?x?xf32>
  return %out : memref<?x?x?xf32>
}

// CHECK-LABEL: @slice
// CHECK-SAME: (%[[INPUT:.*]]: memref<?x?xf32>, %[[OUT:.*]]: memref<?x?xf32>) -> memref<?x?xf32>
func @slice(%input: memref<?x?xf32>, %out: memref<?x?xf32>) -> memref<?x?xf32> {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.slice"(%input, %out) {
    start_indices = dense<[5,6]> : tensor<2xi64>,
    limit_indices = dense<[-1,-1]> : tensor<2xi64>,
    strides = dense<[7,8]> : tensor<2xi64>
  } : (memref<?x?xf32>, memref<?x?xf32>) -> ()
  return %out : memref<?x?xf32>
}

// CHECK-LABEL: @broadcast
// CHECK-SAME: (%[[INPUT:.*]]: memref<?xf32>, %[[OUT:.*]]: memref<3x?xf32>) -> memref<3x?xf32>
func @broadcast(%input: memref<?xf32>, %out: memref<3x?xf32>)->memref<3x?xf32>{
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.broadcast"(%input, %out) {
    broadcast_sizes = dense<[3]> : tensor<1xi64>
  } : (memref<?xf32>, memref<3x?xf32>) -> ()
  return %out : memref<3x?xf32>
}

// CHECK-LABEL: @reshape
// CHECK-SAME: (%[[INPUT:.*]]: memref<?x?xf32>, %[[OUT:.*]]: memref<?x4xf32>) -> memref<?x4xf32>
func @reshape(%input: memref<?x?xf32>, %out: memref<?x4xf32>) -> memref<?x4xf32> {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.reshape"(%input, %out) {
  } : (memref<?x?xf32>, memref<?x4xf32>) -> ()
  return %out : memref<?x4xf32>
}

// CHECK-LABEL: @transpose
// CHECK-SAME: (%[[INPUT:.*]]: memref<?x?x?xf32>, %[[OUT:.*]]: memref<?x?x?xf32>) -> memref<?x?x?xf32>
func @transpose(%input: memref<?x?x?xf32>, %out: memref<?x?x?xf32>)->memref<?x?x?xf32>{
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.transpose"(%input, %out) {
    permutation = dense<[2,1,0]> : tensor<3xi64>
  } : (memref<?x?x?xf32>, memref<?x?x?xf32>) -> ()
  return %out : memref<?x?x?xf32>
}

// CHECK-LABEL: @dynamic_pad
func @dynamic_pad(%operand: memref<?x?x?xf32>, %padding_value: memref<f32>, %edge_padding_low: memref<3xi32>, %edge_padding_high: memref<3xi32>, %interior_padding: memref<3xi32>, %out: memref<?x?x?xf32>) -> memref<?x?x?xf32> {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.dynamic_pad"(%operand, %padding_value, %edge_padding_low, %edge_padding_high, %interior_padding, %out) : (memref<?x?x?xf32>, memref<f32>, memref<3xi32>, memref<3xi32>, memref<3xi32>, memref<?x?x?xf32>) -> ()
  return %out : memref<?x?x?xf32>
}

// CHECK-LABEL: @is_finite
// CHECK-SAME: (%[[INPUT:.*]]: memref<?x?x?xf32>, %[[OUT:.*]]: memref<?x?x?xi1>) -> memref<?x?x?xi1>
func @is_finite(%input: memref<?x?x?xf32>, %out: memref<?x?x?xi1>)->memref<?x?x?xi1>{
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.is_finite"(%input, %out) {
  } : (memref<?x?x?xf32>, memref<?x?x?xi1>) -> ()
  // CHECK: return %[[OUT]] : memref<?x?x?xi1>
  return %out : memref<?x?x?xi1>
}

// CHECK-LABEL: @gather
func @gather(%operand: memref<3xi32>, %start_indices: memref<2xi32>, %out: memref<2xi32>) -> memref<2xi32> {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.gather"(%operand, %start_indices, %out) {dimension_numbers = {collapsed_slice_dims = dense<0> : tensor<1xi64>, index_vector_dim = 1 : i64, offset_dims = dense<[]> : tensor<0xi64>, start_index_map = dense<0> : tensor<1xi64>}, indices_are_sorted = false, slice_sizes = dense<1> : tensor<1xi64>} : (memref<3xi32>, memref<2xi32>, memref<2xi32>) -> ()
  return %out : memref<2xi32>
}

// CHECK-LABEL: @dynamic_gather
func @dynamic_gather(%operand: memref<?x?xf32>, %start_indices: memref<?x?xi32>, %slice_sizes: memref<2xi32>, %out: memref<?x?x?xf32>) -> memref<?x?x?xf32> {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.dynamic_gather"(%operand, %start_indices, %slice_sizes, %out) {dimension_numbers = {collapsed_slice_dims = dense<0> : tensor<1xi64>, index_vector_dim = 2 : i64, offset_dims = dense<2> : tensor<1xi64>, start_index_map = dense<0> : tensor<1xi64>}, indices_are_sorted = false} : (memref<?x?xf32>, memref<?x?xi32>, memref<2xi32>, memref<?x?x?xf32>) -> ()
  return %out : memref<?x?x?xf32>
}

// CHECK-LABEL: @concatenate
// CHECK-SAME: (%[[INPUT:.*]]: memref<?x?xf32>, %[[INPUT:.*]]: memref<?x?xf32>, %[[INPUT:.*]]: memref<?x?xf32>, %[[OUT:.*]]: memref<?x?xf32>) -> memref<?x?xf32>
func @concatenate(%input1: memref<?x?xf32>, %input2: memref<?x?xf32>, %input3: memref<?x?xf32>,%out: memref<?x?xf32>)->memref<?x?xf32>{
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.concatenate"(%input1, %input2, %input3, %out) {
    dimension = 1 : i64
  } : (memref<?x?xf32>, memref<?x?xf32>, memref<?x?xf32>, memref<?x?xf32>) -> ()
  return %out : memref<?x?xf32>
}

// CHECK-LABEL: @copy
func @copy(%operand: memref<?x?x?xf32>, %output: memref<?x?x?xf32>) -> memref<?x?x?xf32> {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.copy"(%operand, %output) : (memref<?x?x?xf32>, memref<?x?x?xf32>) -> ()
  return %output : memref<?x?x?xf32>
}

// CHECK-LABEL: @naive_reduce
func @naive_reduce(%operand: memref<?x?x?xf32>, %init_value: memref<f32>, %output: memref<?x?xf32>) -> memref<?x?xf32> {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.reduce"(%operand, %init_value, %output) ( {
    ^bb0(%arg1: memref<f32>, %arg2: memref<f32>, %arg3: memref<f32>):    // no predecessors
      %tmp = memref.alloc() {temp = true} : memref<f32>
      "lmhlo.add"(%arg1, %arg2, %tmp) : (memref<f32>, memref<f32>, memref<f32>) -> ()
      "lmhlo.copy"(%tmp, %arg3) : (memref<f32>, memref<f32>) -> ()
      memref.dealloc %tmp : memref<f32>
      "lmhlo.terminator"() : () -> ()
    }) {dimensions = dense<1> : tensor<1xi64>} : (memref<?x?x?xf32>, memref<f32>, memref<?x?xf32>) -> ()
  return %output : memref<?x?xf32>
}

// CHECK-LABEL: @dynamic_iota
func @dynamic_iota(%size: memref<2xi32>, %output: memref<?x?xi32>) -> memref<?x?xi32> {
  // CHECK-NOT lmhlo
  // CHECK: scf.for
  "lmhlo.dynamic_iota"(%size, %output) {iota_dimension = 1 : i64} : (memref<2xi32>, memref<?x?xi32>) -> ()
  return %output : memref<?x?xi32>
}

// CHECK-LABEL: @non_fusion_dynamic_broadcast_in_dim_gpu
// CHECK-SAME: (%[[INPUT1:.*]]: memref<?xf32, "gpu">, %[[INPUT2:.*]]: memref<3xi32>, %[[OUT:.*]]: memref<?x?x?xf32, "gpu">) -> memref<?x?x?xf32, "gpu">
func @non_fusion_dynamic_broadcast_in_dim_gpu(%input1: memref<?xf32, "gpu">, %input2: memref<3xi32>, %out: memref<?x?x?xf32, "gpu">) -> (memref<?x?x?xf32, "gpu">) {
  // CHECK-NOT lmhlo
  // CHECK: scf.parallel
  "lmhlo.dynamic_broadcast_in_dim"(%input1, %input2, %out) {broadcast_dimensions = dense<2> : tensor<1xi64>} : (memref<?xf32, "gpu">, memref<3xi32>, memref<?x?x?xf32, "gpu">) -> ()
  // CHECK: return %[[OUT]] : memref<?x?x?xf32, "gpu">
  return %out : memref<?x?x?xf32, "gpu">
}

// CHECK-LABEL: @basic_loop_fusion_misc_root
// CHECK-SAME: (%[[INPUT1:.*]]: memref<?xf32>, %[[INPUT2:.*]]: memref<?xf32>, %[[INPUT3:.*]]: memref<3xi32>, %[[TMP_BUF:.*]]: memref<?xf32>, %[[OUT:.*]]: memref<?x?x?xf32>) -> memref<?x?x?xf32>
func @basic_loop_fusion_misc_root(%input1: memref<?xf32>, %input2: memref<?xf32>, %input3: memref<3xi32>, %tmp: memref<?xf32>, %out: memref<?x?x?xf32>) -> (memref<?x?x?xf32>) {
  // CHECK: "lmhlo.fusion"() ( {
  "lmhlo.fusion"() ( {
    // CHECK: lmhlo.add
    // CHECK-NOT lmhlo.dynamic_broadcast_in_dim
    // CHECK: scf.parallel
    "lmhlo.add"(%input1, %input2, %tmp) : (memref<?xf32>, memref<?xf32>, memref<?xf32>) -> ()
    "lmhlo.dynamic_broadcast_in_dim"(%tmp, %input3, %out) {broadcast_dimensions = dense<2> : tensor<1xi64>} : (memref<?xf32>, memref<3xi32>, memref<?x?x?xf32>) -> ()
    // CHECK: "lmhlo.terminator"() : () -> ()
    "lmhlo.terminator"() : () -> ()
  } ) {disc.fusion.name = "test", disc.fusion_type = "kLoop", disc.device = "gpu"} : () -> ()
  // CHECK: return %[[OUT]] : memref<?x?x?xf32>
  return %out : memref<?x?x?xf32>
}

// CHECK-LABEL: @multioutput_loop_fusion_with_dependency
// CHECK-SAME: (%[[INPUT1:.*]]: memref<?xf32>, %[[INPUT2:.*]]: memref<3xi32>, %[[INPUT3:.*]]: memref<?x?x?xf32>, %[[TMP_BUF:.*]]: memref<?x?x?xf32>, %[[OUT1:.*]]: memref<?x?x?xf32>, %[[OUT2:.*]]: memref<?x?x?xf32>) -> (memref<?x?x?xf32>, memref<?x?x?xf32>)
func @multioutput_loop_fusion_with_dependency(%input1: memref<?xf32>, %input2: memref<3xi32>, %input3: memref<?x?x?xf32>, %tmp: memref<?x?x?xf32>, %out_1: memref<?x?x?xf32>, %out_2: memref<?x?x?xf32>) -> (memref<?x?x?xf32>, memref<?x?x?xf32>) {
  // CHECK: "lmhlo.fusion"() ( {
  "lmhlo.fusion"() ( {
    // CHECK: lmhlo.dynamic_broadcast_in_dim
    // CHECK: lmhlo.add
    // CHECK-NOT: lmhlo.multiply
    // CHECK: scf.parallel
    "lmhlo.dynamic_broadcast_in_dim"(%input1, %input2, %tmp) {broadcast_dimensions = dense<2> : tensor<1xi64>} : (memref<?xf32>, memref<3xi32>, memref<?x?x?xf32>) -> ()
    "lmhlo.add"(%input3, %tmp, %out_1) : (memref<?x?x?xf32>, memref<?x?x?xf32>, memref<?x?x?xf32>) -> ()
    "lmhlo.multiply"(%input3, %out_1, %out_2) : (memref<?x?x?xf32>, memref<?x?x?xf32>, memref<?x?x?xf32>) -> ()
    // CHECK: "lmhlo.terminator"() : () -> ()
    "lmhlo.terminator"() : () -> ()
  }) {disc.fusion.name = "test", disc.fusion_type = "kLoop", disc.device = "gpu"} : () -> ()
  // CHECK: return %[[OUT1]], %[[OUT2]] : memref<?x?x?xf32>, memref<?x?x?xf32>
  return %out_1, %out_2 : memref<?x?x?xf32>, memref<?x?x?xf32>
}

// CHECK-LABEL: @multioutput_loop_fusion_without_dependency
// CHECK-SAME: (%[[INPUT1:.*]]: memref<?xf32>, %[[INPUT2:.*]]: memref<3xi32>, %[[INPUT3:.*]]: memref<?x?x?xf32>, %[[TMP_BUF:.*]]: memref<?x?x?xf32>, %[[OUT1:.*]]: memref<?x?x?xf32>, %[[OUT2:.*]]: memref<?x?x?xf32>) -> (memref<?x?x?xf32>, memref<?x?x?xf32>)
func @multioutput_loop_fusion_without_dependency(%input1: memref<?xf32>, %input2: memref<3xi32>, %input3: memref<?x?x?xf32>, %tmp: memref<?x?x?xf32>, %out_1: memref<?x?x?xf32>, %out_2: memref<?x?x?xf32>) -> (memref<?x?x?xf32>, memref<?x?x?xf32>) {
  // CHECK: "lmhlo.fusion"() ( {
  "lmhlo.fusion"() ( {
    // CHECK: lmhlo.dynamic_broadcast_in_dim
    // CHECK-NOT: lmhlo.add
    // CHECK-NOT: lmhlo.multiply
    // CHECK: scf.parallel
    "lmhlo.dynamic_broadcast_in_dim"(%input1, %input2, %tmp) {broadcast_dimensions = dense<2> : tensor<1xi64>} : (memref<?xf32>, memref<3xi32>, memref<?x?x?xf32>) -> ()
    "lmhlo.add"(%input3, %tmp, %out_1) : (memref<?x?x?xf32>, memref<?x?x?xf32>, memref<?x?x?xf32>) -> ()
    "lmhlo.multiply"(%input3, %tmp, %out_2) : (memref<?x?x?xf32>, memref<?x?x?xf32>, memref<?x?x?xf32>) -> ()
    // CHECK: "lmhlo.terminator"() : () -> ()
    "lmhlo.terminator"() : () -> ()
  }) {disc.fusion.name = "test", disc.fusion_type = "kLoop", disc.device = "gpu"} : () -> ()
  // CHECK: return %[[OUT1]], %[[OUT2]] : memref<?x?x?xf32>, memref<?x?x?xf32>
  return %out_1, %out_2 : memref<?x?x?xf32>, memref<?x?x?xf32>
}

// CHECK-LABEL: @kinput_col_reduce
// CHECK-SAME: (%[[ARG0:.*]]: memref<?x?xf32>, %[[ARG1:.*]]: memref<?x?xf32>, %[[ARG2:.*]]: memref<?xf32>, %[[ARG3:.*]]: memref<f32>) -> memref<?xf32>
func @kinput_col_reduce(%arg0: memref<?x?xf32>, %arg1: memref<?x?xf32>, %arg2: memref<?xf32>, %arg3: memref<f32>) -> memref<?xf32> {
  // initializer for column reduction
  // CHECK: %[[OUTSIZE:.*]] = memref.dim %[[ARG2]], {{.*}} : memref<?xf32>
  // CHECK: scf.parallel (%[[INIT_ITER:.*]]) = (%{{.*}}) to (%{{.*}}) step (%{{.*}}) {
  // CHECK:   %[[DELINEARIZE:.*]] = "disc_shape.delinearize"(%[[INIT_ITER]]
  // CHECK:   %[[INIT_VALUE:.*]] = memref.load %[[ARG3]][] : memref<f32>
  // CHECK:   memref.store %[[INIT_VALUE]], %[[ARG2]][%[[DELINEARIZE]]] : memref<?xf32>
  // CHECK:   scf.yield
  // CHECK: }

  // CHECK-NOT: lmhlo.reduce
  // CHECK-DAG: %[[C0:.*]] = constant 0 : index
  // CHECK-DAG: %[[C1:.*]] = constant 1 : index
  // CHECK: %[[ROWS:.*]] = memref.dim %[[ARG1]], %[[C0]] : memref<?x?xf32>
  // CHECK: %[[COLS:.*]] = memref.dim %[[ARG1]], %[[C1]] : memref<?x?xf32>
  // CHECK-DAG: %[[C256:.*]] = constant 256 : index
  // CHECK-DAG: %[[C8:.*]] = constant 8 : index
  // CHECK-DAG: %[[C32:.*]] = constant 32 : index
  // CHECK-DAG: %[[BLKS_PER_COL:.*]] = ceildivi_signed %[[COLS]], %[[C8]] : index
  // CHECK-DAG: %[[BLKS_PER_ROW:.*]] = ceildivi_signed %[[ROWS]], %[[C32]] : index
  // CHECK-DAG: %[[BLKS:.*]] = muli %[[BLKS_PER_COL]], %[[BLKS_PER_ROW]] : index
  // CHECK: scf.parallel (%[[H_IDX:.*]], %[[W_IDX:.*]]) = (%[[C0]], %[[C0]]) to (%[[BLKS]], %[[C256]]) step (%[[C1]], %[[C1]])
  // CHECK: %[[DATA:.*]] = memref.load %arg3[] : memref<f32>
  // CHECK: atomic_rmw addf %[[TMP:.*]], %[[ARG2]]
  "lmhlo.fusion"() ( {
    "lmhlo.abs"(%arg0, %arg1) : (memref<?x?xf32>, memref<?x?xf32>) -> ()
    "lmhlo.reduce"(%arg1, %arg3, %arg2) ( {
    ^bb0(%arg4: memref<f32>, %arg5: memref<f32>, %arg6: memref<f32>):  // no predecessors
      "lmhlo.add"(%arg4, %arg5, %arg6) : (memref<f32>, memref<f32>, memref<f32>) -> ()
      "lmhlo.terminator"() : () -> ()
    }) {dimensions = dense<0> : tensor<1xi64>} : (memref<?x?xf32>, memref<f32>, memref<?xf32>) -> ()
    // CHECK: "lmhlo.terminator"() : () -> ()
    "lmhlo.terminator"() : () -> ()
  }) {disc.fusion.name = "simple_kinput_reduce__2_1_0", disc.fusion_type = "kColReduction", disc.device = "gpu"} : () -> ()
  // CHECK: return %[[ARG2]] : memref<?xf32>
  return %arg2 : memref<?xf32>
}

// CHECK-LABEL: @kinput_row_reduce_schedule_2_no_vec
// CHECK-SAME: (%[[ARG0:.*]]: memref<?x?xf32>, %[[ARG1:.*]]: memref<?x?xf32>, %[[ARG2:.*]]: memref<?xf32>, %[[ARG3:.*]]: memref<f32>) -> memref<?xf32>
func @kinput_row_reduce_schedule_2_no_vec(%arg0: memref<?x?xf32>, %arg1: memref<?x?xf32>, %arg2: memref<?xf32>, %arg3: memref<f32>) -> memref<?xf32> {
  // CHECK-NOT: lmhlo.reduce
  // CHECK-DAG: %[[C0:.*]] = constant 0 : index
  // CHECK-DAG: %[[C1:.*]] = constant 1 : index
  // CHECK-DAG: %[[HIGHT:.*]] = memref.dim %[[ARG1]], %[[C0]] : memref<?x?xf32>
  // CHECK-DAG: %[[WIDTH:.*]] = memref.dim %[[ARG1]], %[[C1]] : memref<?x?xf32>
  // CHECK-DAG: %[[BLOCK_SIZE:.*]] = constant 256 : index
  // CHECK-DAG: %[[ROW_PER_BLOCK:.*]] = constant 8 : index
  // CHECK: scf.parallel (%[[H_IDX:.*]], %[[W_IDX:.*]]) = (%[[C0]], %[[C0]]) to (%[[HIGHT]], %[[BLOCK_SIZE]]) step (%[[ROW_PER_BLOCK]], %[[C1]])
  // CHECK: gpu.shuffle
  "lmhlo.fusion"() ( {
    "lmhlo.abs"(%arg0, %arg1) : (memref<?x?xf32>, memref<?x?xf32>) -> ()
    "lmhlo.reduce"(%arg1, %arg3, %arg2) ( {
    ^bb0(%arg4: memref<f32>, %arg5: memref<f32>, %arg6: memref<f32>):  // no predecessors
      "lmhlo.add"(%arg4, %arg5, %arg6) : (memref<f32>, memref<f32>, memref<f32>) -> ()
      "lmhlo.terminator"() : () -> ()
    }) {dimensions = dense<1> : tensor<1xi64>} : (memref<?x?xf32>, memref<f32>, memref<?xf32>) -> ()
    "lmhlo.terminator"() : () -> ()
  }) {disc.fusion.name = "kinput_row_reduce_schedule_2", disc_row_reduction_schedule_hint = 2 : i32, disc.fusion_type = "kRowReduction", disc.device = "gpu"} : () -> ()
  // CHECK: "lmhlo.terminator"() : () -> ()
  // CHECK: disc_row_reduction_schedule_hint = 2
  // CHECK: return %[[ARG2]] : memref<?xf32>
  return %arg2 : memref<?xf32>
}

// CHECK-LABEL: @kinput_row_reduce_schedule_2_vec2
// CHECK-SAME: (%[[ARG0:.*]]: memref<?x?xf32>, %[[ARG1:.*]]: memref<?x?xf32>, %[[ARG2:.*]]: memref<?xf32>, %[[ARG3:.*]]: memref<f32>) -> memref<?xf32>
func @kinput_row_reduce_schedule_2_vec2(%arg0: memref<?x?xf32>, %arg1: memref<?x?xf32>, %arg2: memref<?xf32>, %arg3: memref<f32>) -> memref<?xf32> {
  // CHECK-NOT: lmhlo.reduce
  // CHECK-DAG: %[[C0:.*]] = constant 0 : index
  // CHECK-DAG: %[[C1:.*]] = constant 1 : index
  // CHECK-DAG: %[[HIGHT:.*]] = memref.dim %[[ARG1]], %[[C0]] : memref<?x?xf32>
  // CHECK-DAG: %[[WIDTH:.*]] = memref.dim %[[ARG1]], %[[C1]] : memref<?x?xf32>
  // CHECK-DAG: %[[BLOCK_SIZE:.*]] = constant 256 : index
  // CHECK-DAG: %[[ROW_PER_BLOCK:.*]] = constant 16 : index
  // CHECK: scf.parallel (%[[H_IDX:.*]], %[[W_IDX:.*]]) = (%[[C0]], %[[C0]]) to (%[[HIGHT]], %[[BLOCK_SIZE]]) step (%[[ROW_PER_BLOCK]], %[[C1]])
  // CHECK: gpu.shuffle
  // Adjacent store for vectorization optimization.
  // CHECK: memref.assume_alignment %[[ARG2]], 8 : memref<?xf32>
  // CHECK: memref.store %[[RES1:.*]], %[[ARG2]]
  // CHECK: memref.store %[[RES2:.*]], %[[ARG2]]
  "lmhlo.fusion"() ( {
    "lmhlo.abs"(%arg0, %arg1) : (memref<?x?xf32>, memref<?x?xf32>) -> ()
    "lmhlo.reduce"(%arg1, %arg3, %arg2) ( {
    ^bb0(%arg4: memref<f32>, %arg5: memref<f32>, %arg6: memref<f32>):  // no predecessors
      "lmhlo.add"(%arg4, %arg5, %arg6) : (memref<f32>, memref<f32>, memref<f32>) -> ()
      "lmhlo.terminator"() : () -> ()
    }) {dimensions = dense<1> : tensor<1xi64>} : (memref<?x?xf32>, memref<f32>, memref<?xf32>) -> ()
    "lmhlo.terminator"() : () -> ()
  }) {disc.fusion.name = "kinput_row_reduce_schedule_2", disc_row_reduction_schedule_hint = 2 : i32, disc_vectorize_hint = 2 : i32, disc.fusion_type = "kRowReduction", disc.device = "gpu"} : () -> ()
  // CHECK: "lmhlo.terminator"() : () -> ()
  // CHECK: disc_row_reduction_schedule_hint = 2
  // CHECK: disc_vectorize_hint = 2
  // CHECK: return %[[ARG2]] : memref<?xf32>
  return %arg2 : memref<?xf32>
}

// CHECK-LABEL: @kinput_row_reduce_schedule_1_no_vec
// CHECK-SAME: (%[[ARG0:.*]]: memref<?x?xf32>, %[[ARG1:.*]]: memref<?x?xf32>, %[[ARG2:.*]]: memref<?xf32>, %[[ARG3:.*]]: memref<f32>) -> memref<?xf32>
func @kinput_row_reduce_schedule_1_no_vec(%arg0: memref<?x?xf32>, %arg1: memref<?x?xf32>, %arg2: memref<?xf32>, %arg3: memref<f32>) -> memref<?xf32> {
  // CHECK-NOT: lmhlo.reduce
  // CHECK-DAG: %[[C0:.*]] = constant 0 : index
  // CHECK-DAG: %[[C1:.*]] = constant 1 : index
  // CHECK-DAG: %[[HIGHT:.*]] = memref.dim %[[ARG1]], %[[C0]] : memref<?x?xf32>
  // CHECK-DAG: %[[WIDTH:.*]] = memref.dim %[[ARG1]], %[[C1]] : memref<?x?xf32>
  // CHECK-DAG: %[[BLOCK_SIZE:.*]] = constant 256 : index
  // CHECK: %[[VEC_SIZE:.*]] = constant 1 : index
  // CHECK: %[[BLOCK_NUMBER:.*]] = divi_unsigned %[[HIGHT]], %[[VEC_SIZE]] : index
  // CHECK: scf.parallel (%[[H_IDX:.*]], %[[W_IDX:.*]]) = (%[[C0]], %[[C0]]) to (%[[BLOCK_NUMBER]], %[[BLOCK_SIZE]]) step (%[[C1]], %[[C1]])
  // CHECK: %[[SMEM:.*]] = memref.alloc() : memref<32xf32, 3>
  // CHECK: scf.for %[[W_LOCAL_IDX:.*]] = %[[TID:.*]] to %[[WIDTH]] step %[[BLOCK_SIZE]]
  // First round reduce.
  // CHECK: gpu.shuffle
  // CHECK: gpu.barrier
  // CHECK: memref.load %[[SMEM]]
  // Second round reduce.
  // CHECK: gpu.shuffle
  "lmhlo.fusion"() ( {
    "lmhlo.abs"(%arg0, %arg1) : (memref<?x?xf32>, memref<?x?xf32>) -> ()
    "lmhlo.reduce"(%arg1, %arg3, %arg2) ( {
    ^bb0(%arg4: memref<f32>, %arg5: memref<f32>, %arg6: memref<f32>):  // no predecessors
      "lmhlo.add"(%arg4, %arg5, %arg6) : (memref<f32>, memref<f32>, memref<f32>) -> ()
      "lmhlo.terminator"() : () -> ()
    }) {dimensions = dense<1> : tensor<1xi64>} : (memref<?x?xf32>, memref<f32>, memref<?xf32>) -> ()
    "lmhlo.terminator"() : () -> ()
  }) {disc.fusion.name = "kinput_row_reduce_schedule_1", disc_row_reduction_schedule_hint = 1 : i32, disc.fusion_type = "kRowReduction", disc.device = "gpu"} : () -> ()
  // CHECK: "lmhlo.terminator"() : () -> ()
  // CHECK: disc_row_reduction_schedule_hint = 1
  // CHECK: return %[[ARG2]] : memref<?xf32>
  return %arg2 : memref<?xf32>
}

// CHECK-LABEL: @kinput_row_reduce_schedule_1_vec2
// CHECK-SAME: (%[[ARG0:.*]]: memref<?x?xf32>, %[[ARG1:.*]]: memref<?x?xf32>, %[[ARG2:.*]]: memref<?xf32>, %[[ARG3:.*]]: memref<f32>) -> memref<?xf32>
func @kinput_row_reduce_schedule_1_vec2(%arg0: memref<?x?xf32>, %arg1: memref<?x?xf32>, %arg2: memref<?xf32>, %arg3: memref<f32>) -> memref<?xf32> {
  // CHECK-NOT: lmhlo.reduce
  // CHECK-DAG: %[[C0:.*]] = constant 0 : index
  // CHECK-DAG: %[[C1:.*]] = constant 1 : index
  // CHECK-DAG: %[[HIGHT:.*]] = memref.dim %[[ARG1]], %[[C0]] : memref<?x?xf32>
  // CHECK-DAG: %[[WIDTH:.*]] = memref.dim %[[ARG1]], %[[C1]] : memref<?x?xf32>
  // CHECK-DAG: %[[BLOCK_SIZE:.*]] = constant 256 : index
  // CHECK: %[[VEC_SIZE:.*]] = constant 2 : index
  // CHECK: %[[BLOCK_NUMBER:.*]] = divi_unsigned %[[HIGHT]], %[[VEC_SIZE]] : index
  // CHECK: scf.parallel (%[[H_IDX:.*]], %[[W_IDX:.*]]) = (%[[C0]], %[[C0]]) to (%[[BLOCK_NUMBER]], %[[BLOCK_SIZE]]) step (%[[C1]], %[[C1]])
  // CHECK: %[[SMEM:.*]] = memref.alloc() : memref<32xf32, 3>
  // CHECK: scf.for %[[W_LOCAL_IDX:.*]] = %[[TID:.*]] to %[[WIDTH]] step %[[BLOCK_SIZE]]
  // First round reduce.
  // CHECK: gpu.shuffle
  // CHECK: gpu.barrier
  // CHECK: memref.load %[[SMEM]]
  // Second round reduce.
  // CHECK: gpu.shuffle
  // Adjacent store for vectorization optimization.
  // CHECK: memref.assume_alignment %[[ARG2]], 8 : memref<?xf32>
  // CHECK: memref.store %[[RES1:.*]], %[[ARG2]]
  // CHECK: memref.store %[[RES2:.*]], %[[ARG2]]
  "lmhlo.fusion"() ( {
    "lmhlo.abs"(%arg0, %arg1) : (memref<?x?xf32>, memref<?x?xf32>) -> ()
    "lmhlo.reduce"(%arg1, %arg3, %arg2) ( {
    ^bb0(%arg4: memref<f32>, %arg5: memref<f32>, %arg6: memref<f32>):  // no predecessors
      "lmhlo.add"(%arg4, %arg5, %arg6) : (memref<f32>, memref<f32>, memref<f32>) -> ()
      "lmhlo.terminator"() : () -> ()
    }) {dimensions = dense<1> : tensor<1xi64>} : (memref<?x?xf32>, memref<f32>, memref<?xf32>) -> ()
    "lmhlo.terminator"() : () -> ()
  }) {disc.fusion.name = "kinput_row_reduce_schedule_1", disc_row_reduction_schedule_hint = 1 : i32, disc_vectorize_hint = 2 : i32, disc.fusion_type = "kRowReduction", disc.device = "gpu"} : () -> ()
  // CHECK: "lmhlo.terminator"() : () -> ()
  // CHECK: disc_row_reduction_schedule_hint = 1
  // CHECK: disc_vectorize_hint = 2
  // CHECK: return %[[ARG2]] : memref<?xf32>
  return %arg2 : memref<?xf32>
}