//
//  Renderer.swift
//  RubiksCubeShared
//
//  Created by Administrator on 24/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Metal
import MetalKit
import simd

private let RED = simd_float4(1, 0, 0, 1)
private let GREEN = simd_float4(0, 0.5, 0, 1)
private let BLUE = simd_float4(0, 0, 1, 1)
private let YELLOW = simd_float4(1, 1, 0, 1)
private let DARK_ORANGE = simd_float4(1, 0.549, 0, 1)
private let GHOST_WHITE = simd_float4(0.973, 0.973, 1, 1)
private let DARK_GREY = simd_float4(0.157, 0.157, 0.157, 1)

class Renderer: NSObject, MTKViewDelegate, KeyboardControlDelegate {
    
    private struct UIPiece {
        let coords: Coords
        let modelMatrix: matrix_float4x4
        let colorMap: [simd_float4]
        let colorMapBuffer: MTLBuffer
    }
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let flatPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var viewMatrix: matrix_float4x4
    private var projectionMatrix: matrix_float4x4
    private let mtkMesh: MTKMesh
    private var colorMapIndices: [Int32]
    private let colorMapIndicesBuffer: MTLBuffer
    private var uiPieces: [UIPiece]
    private let quat0: simd_quatf
    private let quat1: simd_quatf
    private var iter = 0
    
    init?(mtkView: MTKView, bundle: Bundle? = nil) {
        self.device = mtkView.device!
        mtkView.depthStencilPixelFormat = MTLPixelFormat.depth32Float
        // mtkView.sampleCount = 4
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        
        do {
            flatPipelineState = try Renderer.buildRenderPipelineState(device: device,
                                                                      mtkView: mtkView,
                                                                      bundle: bundle)
        } catch {
            print("Unable to compile render pipeline state. Error info: \(error)")
            return nil
        }
        
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDesciptor.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: depthStateDesciptor)!
        
        let cubeSize = 3
        
        viewMatrix = matrix_lookat(eye: simd_float3(2, 0.8 * Float(cubeSize), 2.0 * Float(cubeSize)),
                                   point: simd_float3(),
                                   up: simd_float3(0, 1, 0))
        projectionMatrix = matrix_identity_float4x4
        
        let url = (bundle ?? Bundle.main).url(forResource: "cube-bevelled", withExtension: "obj")
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<FlatVertex>.stride
        let meshDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        (meshDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url!,
                             vertexDescriptor: meshDescriptor,
                             bufferAllocator: allocator)
        
        let mdlMesh = asset.childObjects(of: MDLMesh.self).first as! MDLMesh
        try! mdlMesh.makeVerticesUniqueAndReturnError()
        mtkMesh = try! MTKMesh(mesh: mdlMesh, device: device)
        
        let submesh = mtkMesh.submeshes[0]
        let indicesCount = submesh.indexCount
        let indicesBuffer = submesh.indexBuffer.buffer
        let indices = indicesBuffer.contents().bindMemory(to: Int32.self, capacity: indicesCount)
        
        let vertexCount = mtkMesh.vertexCount
        let vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        let vertices = vertexBuffer.contents().bindMemory(to: FlatVertex.self, capacity: vertexCount)
        
        colorMapIndices = [Int32](repeating: 6, count: vertexCount)
        for i in stride(from: 0, to: indicesCount, by: 3) {
            let vi1 = Int((indices + i + 0).pointee)
            let vi2 = Int((indices + i + 1).pointee)
            let vi3 = Int((indices + i + 2).pointee)
            let v1 = (vertices + vi1).pointee
            let v2 = (vertices + vi2).pointee
            let v3 = (vertices + vi3).pointee
            let vs = [v1, v2, v3]
            let tuples: [((FlatVertex) -> Bool, Int32)] = [
                ({ v in v.position.y == +1 }, 0),
                ({ v in v.position.y == -1 }, 1),
                ({ v in v.position.x == -1 }, 2),
                ({ v in v.position.x == +1 }, 3),
                ({ v in v.position.z == +1 }, 4),
                ({ v in v.position.z == -1 }, 5)
            ]
            var colorMapIndex: Int32? = nil
            tuples.forEach { (predicate, cmi) in
                if vs.allSatisfy(predicate) {
                    colorMapIndex = cmi
                }
            }
            if colorMapIndex != nil {
                colorMapIndices[vi1] = colorMapIndex!
                colorMapIndices[vi2] = colorMapIndex!
                colorMapIndices[vi3] = colorMapIndex!
            }
        }
        let colorMapIndicesBufferLength = MemoryLayout<Int32>.stride * colorMapIndices.count
        colorMapIndicesBuffer = device.makeBuffer(bytes: colorMapIndices,
                                                  length: colorMapIndicesBufferLength,
                                                  options: [])!
        
        uiPieces = [UIPiece]()
        let solvedCube = makeSolvedCube(cubeSize: cubeSize)
        let cubeDimensions = getCubeDimensions(cubeSize: cubeSize)
        let scale = matrix4x4_scale(0.5, 0.5, 0.5)
        for logicPiece in solvedCube {
            let x = Float(logicPiece.coords.x)
            let y = Float(logicPiece.coords.y)
            let z = Float(logicPiece.coords.z)
            func towardsOrigin(_ v: Float) -> Float { v < 0 ? +0.5 : -0.5 }
            let translation1 = cubeDimensions.isEvenSizedCube
                ? matrix4x4_translation(towardsOrigin(x), towardsOrigin(y), towardsOrigin(z))
                : matrix_identity_float4x4
            let translation2 = matrix4x4_translation(x, y, z)
            let modelMatrix = translation2 * translation1 * scale
            let colorMap = [
                logicPiece.visibleFaces.up ? BLUE : DARK_GREY,
                logicPiece.visibleFaces.down ? GREEN : DARK_GREY,
                logicPiece.visibleFaces.left ? RED : DARK_GREY,
                logicPiece.visibleFaces.right ? DARK_ORANGE : DARK_GREY,
                logicPiece.visibleFaces.front ? YELLOW : DARK_GREY,
                logicPiece.visibleFaces.back ? GHOST_WHITE : DARK_GREY,
                DARK_GREY
            ]
            let colorMapBufferLength = MemoryLayout<simd_float4>.stride * colorMap.count
            let colorMapBuffer = device.makeBuffer(bytes: colorMap, length: colorMapBufferLength, options: [])!
            let uiPiece = UIPiece(coords: logicPiece.coords,
                                  modelMatrix: modelMatrix,
                                  colorMap: colorMap,
                                  colorMapBuffer: colorMapBuffer)
            uiPieces.append(uiPiece)
        }
        
        quat0 = simd_quatf(angle: 0, axis: simd_float3(0, 1, 0))
        quat1 = simd_quatf(angle: Float.pi / 4, axis: simd_float3(0, 1, 0))
        
        super.init()
        
        let allMoves = makeMoveIdsToMoves(cubeSize: cubeSize)
        let scrambleMoves = [allMoves[5]!, allMoves[13]!, allMoves[9]!, allMoves[11]!]
        let unscrambleMoves = Array(scrambleMoves.map { move in allMoves[move.oppositeId]! }.reversed())
        print(scrambleMoves)
        print(unscrambleMoves)
        let scrambledCube = makeMoves(moves: scrambleMoves, initialCube: solvedCube)
        let unscrambledCube = makeMoves(moves: unscrambleMoves, initialCube: scrambledCube)
        print("solvedCube:")
        solvedCube.forEach { piece in print("id: \(piece.id); coords: \(piece.coords)")}
        print("scrambledCube:")
        scrambledCube.forEach { piece in print("id: \(piece.id); coords: \(piece.coords)")}
        print("unscrambledCube:")
        unscrambledCube.forEach { piece in print("id: \(piece.id); coords: \(piece.coords)")}
    }
    
    func onSwitchFractal() {
    }
    
    func onSwitchColorMap() {
    }
    
    class func buildRenderPipelineState(device: MTLDevice,
                                        mtkView: MTKView,
                                        bundle: Bundle?) throws -> MTLRenderPipelineState {
        let library = bundle != nil
            ? try device.makeDefaultLibrary(bundle: bundle!)
            : device.makeDefaultLibrary()
        
        let vertexFunction = library?.makeFunction(name: "vertexFlatShader")
        let fragmentFunction = library?.makeFunction(name: "fragmentFlatShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "FlatRenderPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.sampleCount = mtkView.sampleCount
        pipelineDescriptor.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
        
        let colorAttachments0 = pipelineDescriptor.colorAttachments[0]!
        colorAttachments0.pixelFormat = mtkView.colorPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func renderPieces(renderEncoder: MTLRenderCommandEncoder) {
        var uniforms = FlatUniforms()
        uniforms.modelMatrix = matrix_identity_float4x4
        uniforms.viewMatrix = viewMatrix
        uniforms.projectionMatrix = projectionMatrix
        let uniformsLength = MemoryLayout<FlatUniforms>.stride
        renderEncoder.pushDebugGroup("Draw Piece")
        renderEncoder.setRenderPipelineState(flatPipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.front)
        renderEncoder.setVertexBuffer(mtkMesh.vertexBuffers[0].buffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(colorMapIndicesBuffer, offset: 0, index: 3)
        let submesh = mtkMesh.submeshes[0]
        for uiPiece in uiPieces {
            let rotation = matrix_float4x4(simd_slerp(quat0, quat1, Float(iter) / 60 / 2))
            uniforms.modelMatrix = rotation * uiPiece.modelMatrix
            renderEncoder.setVertexBytes(&uniforms, length: uniformsLength, index: 0)
            renderEncoder.setVertexBuffer(uiPiece.colorMapBuffer, offset: 0, index: 2)
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
        }
        renderEncoder.popDebugGroup()
    }
    
    func draw(in view: MTKView) {
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let renderPassDescriptor = view.currentRenderPassDescriptor
            if let renderPassDescriptor = renderPassDescriptor,
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderPieces(renderEncoder: renderEncoder)
                renderEncoder.endEncoding()
            }
            view.currentDrawable.map(commandBuffer.present)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            iter += 1
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(65),
                                                         aspectRatio:aspect,
                                                         nearZ: 0.1,
                                                         farZ: 100.0)
        
    }
}
