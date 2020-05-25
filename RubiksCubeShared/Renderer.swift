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
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let flatPipelineState: MTLRenderPipelineState
    private var viewMatrix: matrix_float4x4
    private var projectionMatrix: matrix_float4x4
    private let mtkMesh: MTKMesh
    private let colorMap: [simd_float4]
    private let colorMapBuffer: MTLBuffer
    private var colorMapIndices: [Int32]
    private let colorMapIndicesBuffer: MTLBuffer
    
    init?(mtkView: MTKView, bundle: Bundle? = nil) {
        self.device = mtkView.device!
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
        
        viewMatrix = matrix_lookat(eye: simd_float3(2, 2, -5),
                                   point: simd_float3(),
                                   up: simd_float3(0, 1, 0))
        projectionMatrix = matrix_identity_float4x4
        
        colorMap = [RED, GREEN, BLUE, YELLOW, DARK_ORANGE, GHOST_WHITE, DARK_GREY]
        let colorMapBufferLength = MemoryLayout<simd_float4>.stride * colorMap.count
        colorMapBuffer = device.makeBuffer(bytes: colorMap, length: colorMapBufferLength, options: [])!
        
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
            let dir1 = v2.position - v1.position
            let dir2 = v3.position - v1.position
            let n = normalize(simd_cross(dir1, dir2))
            if n.x.closeTo(1) {
                colorMapIndices[vi1] = 0
                colorMapIndices[vi2] = 0
                colorMapIndices[vi3] = 0
                continue
            }
            if n.x.closeTo(-1) {
                colorMapIndices[vi1] = 1
                colorMapIndices[vi2] = 1
                colorMapIndices[vi3] = 1
                continue
            }
            if n.y.closeTo(1) {
                colorMapIndices[vi1] = 2
                colorMapIndices[vi2] = 2
                colorMapIndices[vi3] = 2
                continue
            }
            if n.y.closeTo(-1) {
                colorMapIndices[vi1] = 3
                colorMapIndices[vi2] = 3
                colorMapIndices[vi3] = 3
                continue
            }
            if n.z.closeTo(1) {
                colorMapIndices[vi1] = 4
                colorMapIndices[vi2] = 4
                colorMapIndices[vi3] = 4
                continue
            }
            if n.z.closeTo(-1) {
                colorMapIndices[vi1] = 5
                colorMapIndices[vi2] = 5
                colorMapIndices[vi3] = 5
                continue
            }
        }
        let colorMapIndicesBufferLength = MemoryLayout<Int32>.stride * colorMapIndices.count
        colorMapIndicesBuffer = device.makeBuffer(bytes: colorMapIndices,
                                                  length: colorMapIndicesBufferLength,
                                                  options: [])!
        
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
        
        let colorAttachments0 = pipelineDescriptor.colorAttachments[0]!
        colorAttachments0.pixelFormat = mtkView.colorPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func renderCube(renderEncoder: MTLRenderCommandEncoder) {
        var uniforms = FlatUniforms()
        uniforms.modelMatrix = matrix4x4_scale(0.5, 0.5, 0.5)
        uniforms.viewMatrix = viewMatrix
        uniforms.projectionMatrix = projectionMatrix
        let uniformsLength = MemoryLayout<FlatUniforms>.stride
        renderEncoder.pushDebugGroup("Draw Cube")
        renderEncoder.setRenderPipelineState(flatPipelineState)
        renderEncoder.setCullMode(.front)
        renderEncoder.setVertexBytes(&uniforms, length: uniformsLength, index: 0)
        renderEncoder.setVertexBuffer(mtkMesh.vertexBuffers[0].buffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(colorMapBuffer, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(colorMapIndicesBuffer, offset: 0, index: 3)
        let submesh = mtkMesh.submeshes[0]
        renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                            indexCount: submesh.indexCount,
                                            indexType: submesh.indexType,
                                            indexBuffer: submesh.indexBuffer.buffer,
                                            indexBufferOffset: submesh.indexBuffer.offset)
        renderEncoder.popDebugGroup()
    }
    
    func draw(in view: MTKView) {
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            let renderPassDescriptor = view.currentRenderPassDescriptor
            if let renderPassDescriptor = renderPassDescriptor,
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                renderCube(renderEncoder: renderEncoder)
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
