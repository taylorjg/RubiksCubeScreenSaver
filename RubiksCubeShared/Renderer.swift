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

class Renderer: NSObject, MTKViewDelegate, KeyboardControlDelegate {
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let flatPipelineState: MTLRenderPipelineState
    private let mesh: MDLMesh
    private var viewMatrix: matrix_float4x4
    private var projectionMatrix: matrix_float4x4
    
    init?(mtkView: MTKView, bundle: Bundle? = nil) {
        self.device = mtkView.device!
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
        
        viewMatrix = matrix_lookat(eye: simd_float3(0, 0, -2),
                                   point: simd_float3(),
                                   up: simd_float3(0, 1, 0))
        projectionMatrix = matrix_identity_float4x4
        
        let url = (bundle ?? Bundle.main).url(forResource: "cube-bevelled", withExtension: "obj")
        let asset = MDLAsset(url: url!)
        mesh = asset.childObjects(of: MDLMesh.self).first as! MDLMesh
        
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
        
        let colorAttachments0 = pipelineDescriptor.colorAttachments[0]!
        colorAttachments0.pixelFormat = mtkView.colorPixelFormat
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func renderCube(renderEncoder: MTLRenderCommandEncoder) {
        // let submesh = mesh.submeshes![0] as! MDLSubmesh
        let color = simd_float4(1, 0, 0, 1)
        let vertices = [
            FlatVertex(position: simd_float3(0, 0.5, 0), color: color),
            FlatVertex(position: simd_float3(-0.5, -0.5, 0), color: color),
            FlatVertex(position: simd_float3(0.5, -0.5, 0), color: color)
        ]
        let verticesLength = MemoryLayout<FlatVertex>.stride * vertices.count
        var uniforms = FlatUniforms()
        uniforms.modelMatrix = matrix_identity_float4x4
        uniforms.viewMatrix = viewMatrix
        uniforms.projectionMatrix = projectionMatrix
        let uniformsLength = MemoryLayout<FlatUniforms>.stride
        renderEncoder.pushDebugGroup("Draw Cube")
        renderEncoder.setRenderPipelineState(flatPipelineState)
        renderEncoder.setVertexBytes(&uniforms, length: uniformsLength, index: 0)
        renderEncoder.setVertexBytes(vertices, length: verticesLength, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
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
