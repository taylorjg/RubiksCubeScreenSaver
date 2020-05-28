//
//  Logic.swift
//  RubiksCubeShared
//
//  Created by Administrator on 27/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Foundation

struct Faces {
    let up: Bool
    let down: Bool
    let left: Bool
    let right: Bool
    let front: Bool
    let back: Bool
}

private func makeFaces(cubeDimensions: CubeDimensions, coords: Coords) -> Faces {
    return Faces(up: coords.y == cubeDimensions.vmax,
                 down: coords.y == cubeDimensions.vmin,
                 left: coords.x == cubeDimensions.vmin,
                 right: coords.x == cubeDimensions.vmax,
                 front: coords.z == cubeDimensions.vmax,
                 back: coords.z == cubeDimensions.vmin)
}

struct LogicPiece {
    let coords: Coords
    let faces: Faces
    let accumulatedRotations: matrix_float4x4
}

func makeSolvedCube(cubeSize: Int) -> [LogicPiece] {
    let cubeDimensions = getCubeDimensions(cubeSize: cubeSize)
    let allCoordsList = allCoords(cubeSize: cubeSize)
    return allCoordsList.map { coords in
        let faces = makeFaces(cubeDimensions: cubeDimensions, coords: coords)
        return LogicPiece(coords: coords,
                          faces: faces,
                          accumulatedRotations: matrix_identity_float4x4)
    }
}

private func getPieces(cube: [LogicPiece], coordsList: [Coords]) -> [LogicPiece] {
    cube.filter { logicPiece in coordsList.contains(logicPiece.coords) }
}

private func rotatePiece(logicPiece: LogicPiece, rotation: matrix_float4x4) -> LogicPiece {
    let x = Float(logicPiece.coords.x)
    let y = Float(logicPiece.coords.y)
    let z = Float(logicPiece.coords.z)
    let vector = simd_float4(x, y, z, 1)
    let rotated = rotation * vector
    let x2 = Int(round(rotated.x))
    let y2 = Int(round(rotated.y))
    let z2 = Int(round(rotated.z))
    let coords2 = Coords(x2, y2, z2)
    let accumulatedRotations2 = rotation * logicPiece.accumulatedRotations
    return LogicPiece(coords: coords2,
                      faces: logicPiece.faces,
                      accumulatedRotations: accumulatedRotations2)
}

private func rotatePieces(rotation: matrix_float4x4,
                          coordsList: [Coords],
                          cube: [LogicPiece]) -> [LogicPiece] {
    cube.map { logicPiece in
        coordsList.contains(logicPiece.coords)
            ? rotatePiece(logicPiece: logicPiece, rotation: rotation)
            : logicPiece
    }
}

private let angles = [
    radians_from_degrees(90),
    radians_from_degrees(180),
    radians_from_degrees(270)
]

private let rotationsX = angles.map { angle in matrix4x4_rotation(radians: angle, axis: simd_float3(1, 0, 0)) }
private let rotationsY = angles.map { angle in matrix4x4_rotation(radians: angle, axis: simd_float3(0, 1, 0)) }
private let rotationsZ = angles.map { angle in matrix4x4_rotation(radians: angle, axis: simd_float3(0, 0, 1)) }

struct Move {
    let id: Int
    let oppositeId: Int
    let makeMove: ([LogicPiece]) -> [LogicPiece]
    let rotation: matrix_float4x4
    let coordsList: [Coords]
    let numTurns: Int
}

private func makeKvp(id: Int,
                     oppositeId: Int,
                     rotation: matrix_float4x4,
                     coordsList: [Coords],
                     numTurns: Int) -> (Int, Move) {
    let makeMove: ([LogicPiece]) -> [LogicPiece] = { cube in
        rotatePieces(rotation: rotation, coordsList: coordsList, cube: cube)
    }
    let move = Move(id: id,
                    oppositeId: oppositeId,
                    makeMove: makeMove,
                    rotation: rotation,
                    coordsList: coordsList,
                    numTurns: numTurns)
    return (id, move)
}

private func makeKvpsForSlice(rotations: [matrix_float4x4],
                              coordsList: [Coords],
                              index: Int) -> [(Int, Move)] {
    let baseId = index * 3
    let move90Id = baseId
    let move180Id = baseId + 1
    let move270Id = baseId + 2
    let move90Kvp = makeKvp(id: move90Id, oppositeId: move270Id, rotation: rotations[0], coordsList: coordsList, numTurns: 1)
    let move180Kvp = makeKvp(id: move180Id, oppositeId: move180Id, rotation: rotations[1], coordsList: coordsList, numTurns: 2)
    let move270Kvp = makeKvp(id: move270Id, oppositeId: move90Id, rotation: rotations[2], coordsList: coordsList, numTurns: 1)
    return [move90Kvp, move180Kvp, move270Kvp]
}

func makeMoveIdsToMoves(cubeSize: Int) -> [Int: Move] {
    let cubeDimensions = getCubeDimensions(cubeSize: cubeSize)
    let values = cubeDimensions.values
    let allCoordsList = allCoords(cubeSize: cubeSize)
    let slicesX = values.map { x -> ([matrix_float4x4], [Coords]) in
        let coordsList = pitchSliceCoordsList(allCoordsList: allCoordsList, x: x)
        return (rotationsX, coordsList)
    }
    let slicesY = values.map { y -> ([matrix_float4x4], [Coords]) in
        let coordsList = yawSliceCoordsList(allCoordsList: allCoordsList, y: y)
        return (rotationsX, coordsList)
    }
    let slicesZ = values.map { z -> ([matrix_float4x4], [Coords]) in
        let coordsList = rollSliceCoordsList(allCoordsList: allCoordsList, z: z)
        return (rotationsX, coordsList)
    }
    let slices = slicesX + slicesY + slicesZ
    let kvps = slices.enumerated().flatMap { (index, tuple) -> [(Int, Move)] in
        let (rotations, coordsList) = tuple
        return makeKvpsForSlice(rotations: rotations, coordsList: coordsList, index: index)
    }
    return [Int: Move].init(uniqueKeysWithValues: kvps)
}
