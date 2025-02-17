/* Copyright 2021 The TensorFlow Authors. All Rights Reserved.

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

#include "mlir-hlo/Dialect/mhlo/IR/hlo_ops.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/StandardOps/IR/Ops.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/Attributes.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Operation.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/Bufferize.h"
#include "mlir/Transforms/DialectConversion.h"
#include "tensorflow/compiler/mlir/disc/transforms/PassDetail.h"
#include "tensorflow/compiler/mlir/disc/transforms/rewriters.h"

namespace mlir {
namespace disc_ral {

using mhlo::ConstOp;

namespace {

class ConstantOpConverter : public OpConversionPattern<ConstantOp> {
 public:
  using OpConversionPattern<ConstantOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(
      ConstantOp op, ArrayRef<Value> operands,
      ConversionPatternRewriter& rewriter) const override;
};

LogicalResult ConstantOpConverter::matchAndRewrite(
    ConstantOp op, ArrayRef<Value> operands,
    ConversionPatternRewriter& rewriter) const {
  auto resultType = op.getType().dyn_cast<RankedTensorType>();
  if (!resultType) return failure();

  if (resultType.getRank() != 1) return failure();

  auto elemType = resultType.getElementType();
  if (!elemType.isIndex() && !elemType.isa<IntegerType>()) return failure();

  Location loc = op.getLoc();
  DenseElementsAttr attr = op.value().cast<DenseElementsAttr>();
  MemRefType bufferType = MemRefType::get({resultType.getShape()}, elemType);
  Value result = rewriter.create<memref::AllocOp>(loc, bufferType);
  for (auto&& en : llvm::enumerate(attr.getValues<llvm::APInt>())) {
    Value idx = rewriter.create<ConstantIndexOp>(loc, en.index());
    Value val =
        rewriter.create<ConstantIndexOp>(loc, en.value().getSExtValue());
    if (!elemType.isIndex())
      val = rewriter.create<IndexCastOp>(loc, val, elemType);
    rewriter.create<memref::StoreOp>(loc, val, result, idx);
  }

  rewriter.replaceOp(op, {result});
  return success();
}

class IndexCastOpConverter : public OpConversionPattern<IndexCastOp> {
 public:
  using OpConversionPattern<IndexCastOp>::OpConversionPattern;

  LogicalResult matchAndRewrite(
      IndexCastOp op, ArrayRef<Value> operands,
      ConversionPatternRewriter& rewriter) const override;
};

LogicalResult IndexCastOpConverter::matchAndRewrite(
    IndexCastOp op, ArrayRef<Value> operands,
    ConversionPatternRewriter& rewriter) const {
  auto resultType = op.getType().dyn_cast<RankedTensorType>();
  if (!resultType || resultType.getRank() != 1 ||
      !resultType.hasStaticShape()) {
    return failure();
  }
  int64_t dim_size = resultType.getDimSize(0);
  auto elemType = resultType.getElementType();
  if (!elemType.isIndex() && !elemType.isa<IntegerType>()) return failure();
  assert(operands.size() == 1);

  Location loc = op.getLoc();
  MemRefType bufferType = MemRefType::get({resultType.getShape()}, elemType);
  Value result = rewriter.create<memref::AllocOp>(loc, bufferType);
  for (int64_t i = 0; i < dim_size; ++i) {
    Value idx = rewriter.create<ConstantIndexOp>(loc, i);
    Value val = rewriter.create<memref::LoadOp>(loc, operands[0], idx);
    Value casted = rewriter.create<IndexCastOp>(loc, val, elemType);
    rewriter.create<memref::StoreOp>(loc, casted, result, idx);
  }
  rewriter.replaceOp(op, {result});
  return success();
}

class StdBufferizePass : public StdBufferizePassBase<StdBufferizePass> {
  void getDependentDialects(DialectRegistry& registry) const override {
    registry.insert<memref::MemRefDialect>();
  }

  void runOnFunction() override;
};

void StdBufferizePass::runOnFunction() {
  // Setup target legality.
  MLIRContext& ctx = getContext();
  ConversionTarget target(ctx);
  BufferizeTypeConverter typeConverter;

  populateBufferizeMaterializationLegality(target);

  target.addLegalDialect<memref::MemRefDialect>();
  target.addLegalOp<FuncOp, ModuleOp>();
  target.addDynamicallyLegalDialect<StandardOpsDialect>(
      [&](Operation* op) { return typeConverter.isLegal(op); });

  // Setup conversion patterns.
  RewritePatternSet patterns(&ctx);
  // clang-format off
  patterns.insert<ConstantOpConverter,
                  IndexCastOpConverter>(
      typeConverter, &ctx);
  // clang-format on

  // Apply conversion.
  FuncOp func = getFunction();
  if (failed(applyPartialConversion(func, target, std::move(patterns))))
    signalPassFailure();
}

}  // namespace

std::unique_ptr<mlir::FunctionPass> createDiscStdBufferizePass() {
  return std::make_unique<StdBufferizePass>();
}

}  // namespace disc_ral
}  // namespace mlir
