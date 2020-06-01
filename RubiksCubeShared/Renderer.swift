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

struct Settings {
    static let defaultCubeSizes = [2, 3]
    static let defaultPauseInterval = 10
    static let defaultEnableMSAA = false
    
    let cubeSizes: [Int]
    let pauseInterval: Int
    let enableMSAA: Bool
}

extension Settings {
    init() {
        cubeSizes = Settings.defaultCubeSizes
        pauseInterval = Settings.defaultPauseInterval
        enableMSAA = Settings.defaultEnableMSAA
    }
}

private let RED = simd_float4(1, 0, 0, 1)
private let GREEN = simd_float4(0, 0.5, 0, 1)
private let BLUE = simd_float4(0, 0, 1, 1)
private let YELLOW = simd_float4(1, 1, 0, 1)
private let DARK_ORANGE = simd_float4(1, 0.549, 0, 1)
private let GHOST_WHITE = simd_float4(0.973, 0.973, 1, 1)
private let DARK_GREY = simd_float4(0.157, 0.157, 0.157, 1)

class Renderer: NSObject, MTKViewDelegate, KeyboardControlDelegate {
    
    private struct VisualPiece {
        let id: Int
        let modelMatrix: matrix_float4x4
        let rotation: matrix_float4x4
        let colorMap: [simd_float4]
        let colorMapBuffer: MTLBuffer
    }
    
    private struct Animation {
        let ids: [Int]
        let quat0: simd_quatf
        let quat1: simd_quatf
        let totalFrames: Int
        var remainingFrames: Int
        let onCompletion: () -> Void
        mutating func tick() {
            if remainingFrames > 0 {
                remainingFrames -= 1
                if remainingFrames == 0 {
                    onCompletion()
                }
            }
        }
    }
    
    private let settings: Settings
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let flatPipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private var viewMatrix: matrix_float4x4
    private var projectionMatrix: matrix_float4x4
    private let mtkMesh: MTKMesh
    private let colorMapIndicesBuffer: MTLBuffer
    private var cube: [LogicalPiece] = []
    private var scrambleMoves: [Move] = []
    private var unscrambleMoves: [Move] = []
    private var visualPieces: [VisualPiece] = []
    private var animation: Animation?
    private let quat0: simd_quatf
    private let quat1: simd_quatf
    private var iteration = 0
    
    init?(mtkView: MTKView, bundle: Bundle? = nil, settings: Settings) {
        self.settings = settings
        self.device = mtkView.device!
        mtkView.depthStencilPixelFormat = MTLPixelFormat.depth32Float
        if settings.enableMSAA {
            mtkView.sampleCount = 4
        }
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
        
        viewMatrix = matrix_identity_float4x4
        projectionMatrix = matrix_identity_float4x4
        
        mtkMesh = Renderer.loadCubeModel(device: device, bundle: bundle)
        colorMapIndicesBuffer = Renderer.buildColorMapIndicesBuffer(device: device, mtkMesh: mtkMesh)
        
        quat0 = simd_quatf(matrix_identity_float4x4)
        quat1 = simd_quatf(angle: Float.pi / 4, axis: simd_float3(0, 1, 0))
        
        super.init()
        
        scramble()
    }
    
    private func setViewMatrix(cubeSize: Int) {
        let zs = [
            2: 2.0 * 2,
            3: 2.0 * 3,
            4: 2.2 * 4,
            5: 2.4 * 5
        ]
        let z = zs[cubeSize]!
        viewMatrix = matrix_lookat(eye: simd_float3(2, 0.8 * Float(cubeSize), Float(z)),
                                   point: simd_float3(),
                                   up: simd_float3(0, 1, 0))
    }
    
    private class func loadCubeModel(device: MTLDevice, bundle: Bundle?) -> MTKMesh {
        let url = (bundle ?? Bundle.main).url(forResource: "cube-bevelled", withExtension: "obj")
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<FlatVertex>.stride
        let meshDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        (meshDescriptor.attributes[0] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        let allocator = MTKMeshBufferAllocator(device: device)
        let mdlAsset = MDLAsset(url: url!,
                                vertexDescriptor: meshDescriptor,
                                bufferAllocator: allocator)
        let mdlMesh = mdlAsset.childObjects(of: MDLMesh.self).first as! MDLMesh
        try! mdlMesh.makeVerticesUniqueAndReturnError()
        let mtkMesh = try! MTKMesh(mesh: mdlMesh, device: device)
        return mtkMesh
    }
    
    private class func buildColorMapIndicesBuffer(device: MTLDevice, mtkMesh: MTKMesh) -> MTLBuffer {
        
        let submesh = mtkMesh.submeshes[0]
        let indicesCount = submesh.indexCount
        let indicesBuffer = submesh.indexBuffer.buffer
        let indices = indicesBuffer.contents().bindMemory(to: Int32.self, capacity: indicesCount)
        
        let vertexCount = mtkMesh.vertexCount
        let vertexBuffer = mtkMesh.vertexBuffers[0].buffer
        let vertices = vertexBuffer.contents().bindMemory(to: FlatVertex.self, capacity: vertexCount)
        
        var colorMapIndices = [Int32](repeating: 6, count: vertexCount)
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
            if let colorMapIndex = colorMapIndex {
                colorMapIndices[vi1] = colorMapIndex
                colorMapIndices[vi2] = colorMapIndex
                colorMapIndices[vi3] = colorMapIndex
            }
        }
        
        let colorMapIndicesBufferLength = MemoryLayout<Int32>.stride * colorMapIndices.count
        let colorMapIndicesBuffer = device.makeBuffer(bytes: colorMapIndices,
                                                      length: colorMapIndicesBufferLength,
                                                      options: [])!
        
        return colorMapIndicesBuffer
    }
    
    private func createVisualPieces(cubeSize: Int, solvedCube: [LogicalPiece]) -> [VisualPiece] {
        var visualPieces = [VisualPiece]()
        let cubeDimensions = getCubeDimensions(cubeSize: cubeSize)
        let scale = matrix4x4_scale(0.5, 0.5, 0.5)
        for logicalPiece in solvedCube {
            let x = Float(logicalPiece.coords.x)
            let y = Float(logicalPiece.coords.y)
            let z = Float(logicalPiece.coords.z)
            func towardsOrigin(_ v: Float) -> Float { v < 0 ? +0.5 : -0.5 }
            let translation1 = cubeDimensions.isEvenSizedCube
                ? matrix4x4_translation(towardsOrigin(x), towardsOrigin(y), towardsOrigin(z))
                : matrix_identity_float4x4
            let translation2 = matrix4x4_translation(x, y, z)
            let modelMatrix = translation2 * translation1 * scale
            let colorMap = [
                logicalPiece.visibleFaces.up ? BLUE : DARK_GREY,
                logicalPiece.visibleFaces.down ? GREEN : DARK_GREY,
                logicalPiece.visibleFaces.left ? RED : DARK_GREY,
                logicalPiece.visibleFaces.right ? DARK_ORANGE : DARK_GREY,
                logicalPiece.visibleFaces.front ? YELLOW : DARK_GREY,
                logicalPiece.visibleFaces.back ? GHOST_WHITE : DARK_GREY,
                DARK_GREY
            ]
            let colorMapBufferLength = MemoryLayout<simd_float4>.stride * colorMap.count
            let colorMapBuffer = device.makeBuffer(bytes: colorMap, length: colorMapBufferLength, options: [])!
            let visualPiece = VisualPiece(id: logicalPiece.id,
                                          modelMatrix: modelMatrix,
                                          rotation: matrix_identity_float4x4,
                                          colorMap: colorMap,
                                          colorMapBuffer: colorMapBuffer)
            visualPieces.append(visualPiece)
        }
        return visualPieces
    }
    
    private func updateVisualPieces() {
        func findLogicalPiece(id: Int) -> LogicalPiece? {
            cube.first(where: { logicalPiece in logicalPiece.id == id })
        }
        visualPieces = visualPieces.map { visualPiece in
            guard let logicalPiece = findLogicalPiece(id: visualPiece.id) else {
                return visualPiece
            }
            return VisualPiece(id: visualPiece.id,
                               modelMatrix: visualPiece.modelMatrix,
                               rotation: logicalPiece.accumulatedRotations,
                               colorMap: visualPiece.colorMap,
                               colorMapBuffer: visualPiece.colorMapBuffer)
        }
    }
    
    private func startAnimation() {
        guard let move = unscrambleMoves.last else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(settings.pauseInterval)) {
                self.scramble()
            }
            return
        }
        let logicalPieces = getPieces(cube: cube, coordsList: move.coordsList)
        let ids = logicalPieces.map { logicalPiece in logicalPiece.id }
        let totalFrames = 45 * move.numTurns
        animation = Animation(ids: ids,
                              quat0: simd_quatf(matrix_identity_float4x4),
                              quat1: simd_quatf(move.rotation),
                              totalFrames: totalFrames,
                              remainingFrames: totalFrames,
                              onCompletion: completeAnimation)
    }
    
    private func completeAnimation() {
        guard let move = unscrambleMoves.popLast() else {
            return
        }
        cube = move.makeMove(cube)
        updateVisualPieces()
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(0.5)) {
            self.startAnimation()
        }
    }
    
    private func scramble() {
        let ranges = [
            2: 5...10,
            3: 10...20,
            4: 15...25,
            5: 15...30
        ]
        let cubeSize = settings.cubeSizes.randomElement()!
        let numMoves = Int.random(in: ranges[cubeSize] ?? 10...20)
        setViewMatrix(cubeSize: cubeSize)
        let solvedCube = makeSolvedCube(cubeSize: cubeSize)
        visualPieces = createVisualPieces(cubeSize: cubeSize, solvedCube: solvedCube)
        (scrambleMoves, unscrambleMoves) = getRandomMoves(cubeSize: cubeSize, numMoves: numMoves)
        cube = makeMoves(moves: scrambleMoves, initialCube: solvedCube)
        updateVisualPieces()
        startAnimation()
    }
    
    private class func buildRenderPipelineState(device: MTLDevice,
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
    
    private func calcAnimationRotation(visualPiece: VisualPiece) -> matrix_float4x4 {
        guard
            let animation = animation,
            animation.remainingFrames > 0,
            animation.ids.contains(visualPiece.id)
            else { return matrix_identity_float4x4 }
        let completedFrames = animation.totalFrames - animation.remainingFrames
        let t = Float(completedFrames) / Float(animation.totalFrames)
        return matrix_float4x4(simd_slerp(animation.quat0, animation.quat1, t))
    }
    
    private func renderCube(renderEncoder: MTLRenderCommandEncoder) {
        var uniforms = FlatUniforms()
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
        for visualPiece in visualPieces {
            let cubeRotation = matrix_float4x4(simd_slerp(quat0, quat1, Float(iteration) / 60 / 4))
            let animationRotation = calcAnimationRotation(visualPiece: visualPiece)
            let pieceRotation = visualPiece.rotation
            uniforms.modelMatrix = cubeRotation * animationRotation * pieceRotation * visualPiece.modelMatrix
            renderEncoder.setVertexBytes(&uniforms, length: uniformsLength, index: 0)
            renderEncoder.setVertexBuffer(visualPiece.colorMapBuffer, offset: 0, index: 2)
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
        }
        renderEncoder.popDebugGroup()
        animation?.tick()
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
            iteration += 1
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
