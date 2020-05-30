//
//  Logic.swift
//  RubiksCubeShared
//
//  Created by Administrator on 27/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Foundation

struct VisibleFaces {
    let up: Bool
    let down: Bool
    let left: Bool
    let right: Bool
    let front: Bool
    let back: Bool
}

struct LogicalPiece {
    let id: Int
    let coords: Coords
    let visibleFaces: VisibleFaces
    let accumulatedRotations: matrix_float4x4
}

struct Move {
    let id: Int
    let oppositeId: Int
    let makeMove: ([LogicalPiece]) -> [LogicalPiece]
    let rotation: matrix_float4x4
    let coordsList: [Coords]
    let numTurns: Int
}

private func getVisibleFaces(cubeDimensions: CubeDimensions, coords: Coords) -> VisibleFaces {
    return VisibleFaces(up: coords.y == cubeDimensions.vmax,
                        down: coords.y == cubeDimensions.vmin,
                        left: coords.x == cubeDimensions.vmin,
                        right: coords.x == cubeDimensions.vmax,
                        front: coords.z == cubeDimensions.vmax,
                        back: coords.z == cubeDimensions.vmin)
}

func makeSolvedCube(cubeSize: Int) -> [LogicalPiece] {
    let cubeDimensions = getCubeDimensions(cubeSize: cubeSize)
    let allCoordsList = allCoords(cubeSize: cubeSize)
    return allCoordsList.enumerated().map { (index, coords) in
        let visibleFaces = getVisibleFaces(cubeDimensions: cubeDimensions, coords: coords)
        return LogicalPiece(id: index,
                            coords: coords,
                            visibleFaces: visibleFaces,
                            accumulatedRotations: matrix_identity_float4x4)
    }
}

func getPieces(cube: [LogicalPiece], coordsList: [Coords]) -> [LogicalPiece] {
    cube.filter { logicalPiece in coordsList.contains(logicalPiece.coords) }
}

private func rotatePiece(logicalPiece: LogicalPiece, rotation: matrix_float4x4) -> LogicalPiece {
    let x = Float(logicalPiece.coords.x)
    let y = Float(logicalPiece.coords.y)
    let z = Float(logicalPiece.coords.z)
    let vector = simd_float4(x, y, z, 1)
    let rotated = rotation * vector
    let x2 = Int(round(rotated.x))
    let y2 = Int(round(rotated.y))
    let z2 = Int(round(rotated.z))
    let coords2 = Coords(x2, y2, z2)
    let accumulatedRotations2 = rotation * logicalPiece.accumulatedRotations
    return LogicalPiece(id: logicalPiece.id,
                        coords: coords2,
                        visibleFaces: logicalPiece.visibleFaces,
                        accumulatedRotations: accumulatedRotations2)
}

private func rotatePieces(rotation: matrix_float4x4,
                          coordsList: [Coords],
                          cube: [LogicalPiece]) -> [LogicalPiece] {
    cube.map { logicalPiece in
        coordsList.contains(logicalPiece.coords)
            ? rotatePiece(logicalPiece: logicalPiece, rotation: rotation)
            : logicalPiece
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

private func makeKvp(id: Int,
                     oppositeId: Int,
                     rotation: matrix_float4x4,
                     coordsList: [Coords],
                     numTurns: Int) -> (Int, Move) {
    let makeMove: ([LogicalPiece]) -> [LogicalPiece] = { cube in
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
        return (rotationsY, coordsList)
    }
    let slicesZ = values.map { z -> ([matrix_float4x4], [Coords]) in
        let coordsList = rollSliceCoordsList(allCoordsList: allCoordsList, z: z)
        return (rotationsZ, coordsList)
    }
    let slices = slicesX + slicesY + slicesZ
    let kvps = slices.enumerated().flatMap { (index, slice) -> [(Int, Move)] in
        let (rotations, coordsList) = slice
        return makeKvpsForSlice(rotations: rotations, coordsList: coordsList, index: index)
    }
    return [Int: Move](uniqueKeysWithValues: kvps)
}

func makeMoves(moves: [Move], initialCube: [LogicalPiece]) -> [LogicalPiece] {
    moves.reduce(initialCube, { (currentCube, move) in move.makeMove(currentCube) })
}

func getRandomMoves(cubeSize: Int, numMoves: Int) -> ([Move], [Move]) {
    let allMoves = makeMoveIdsToMoves(cubeSize: cubeSize)
    let scrambleMoves = (0..<numMoves).map { _ -> Move in
        let randomMoveId = Int.random(in: 0..<allMoves.count)
        return allMoves[randomMoveId]!
    }
    let unscrambleMoves = scrambleMoves.map { scrambleMove in
        return allMoves[scrambleMove.oppositeId]!
    }
    return (scrambleMoves, unscrambleMoves)
}
