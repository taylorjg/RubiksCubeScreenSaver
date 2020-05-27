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
private let GREEN = simd_float4(0, 1, 0, 1)
private let BLUE = simd_float4(0, 0, 1, 1)
private let YELLOW = simd_float4(1, 1, 0, 1)
private let DARK_ORANGE = simd_float4(1, 0.549, 0, 1)
private let GHOST_WHITE = simd_float4(0.973, 0.973, 1, 1)
private let DARK_GREY = simd_float4(0.157, 0.157, 0.157, 1)

class Renderer: NSObject, MTKViewDelegate, KeyboardControlDelegate {
    
    private struct Piece {
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
    private var pieces: [Piece]
    
    init?(mtkView: MTKView, bundle: Bundle? = nil) {
        self.device = mtkView.device!
        mtkView.depthStencilPixelFormat = MTLPixelFormat.depth32Float
        mtkView.sampleCount = 4
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
        
        viewMatrix = matrix_lookat(eye: simd_float3(2, 2, -5),
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
                ({ v in v.position.x == +1 }, 0),
                ({ v in v.position.x == -1 }, 1),
                ({ v in v.position.y == +1 }, 2),
                ({ v in v.position.y == -1 }, 3),
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

        pieces = [Piece]()
        let scale = matrix4x4_scale(0.5, 0.5, 0.5)
        let solvedCubePieces = makeSolvedCube(cubeSize: 3)
        for solvedCubePiece in solvedCubePieces {
            let x = Float(solvedCubePiece.coords.x)
            let y = Float(solvedCubePiece.coords.y)
            let z = Float(solvedCubePiece.coords.z)
            let translation = matrix4x4_translation(x, y, z)
            let modelMatrix = translation * scale
            let colorMap = [
                solvedCubePiece.faces.right ? RED : DARK_GREY,
                solvedCubePiece.faces.left ? GREEN : DARK_GREY,
                solvedCubePiece.faces.up ? BLUE : DARK_GREY,
                solvedCubePiece.faces.down ? YELLOW : DARK_GREY,
                solvedCubePiece.faces.back ? DARK_ORANGE : DARK_GREY,
                solvedCubePiece.faces.front ? GHOST_WHITE : DARK_GREY,
                DARK_GREY
            ]
            let colorMapBufferLength = MemoryLayout<simd_float4>.stride * colorMap.count
            let colorMapBuffer = device.makeBuffer(bytes: colorMap, length: colorMapBufferLength, options: [])!
            let piece = Piece(modelMatrix: modelMatrix,
                              colorMap: colorMap,
                              colorMapBuffer: colorMapBuffer)
            pieces.append(piece)
        }
        
        super.init()
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
        for piece in pieces {
            uniforms.modelMatrix = piece.modelMatrix
            renderEncoder.setVertexBytes(&uniforms, length: uniformsLength, index: 0)
            renderEncoder.setVertexBuffer(piece.colorMapBuffer, offset: 0, index: 2)
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
