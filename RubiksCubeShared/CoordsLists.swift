//
//  CoordsLists.swift
//  RubiksCubeShared
//
//  Created by Administrator on 27/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Foundation

struct CubeDimensions {
    let values: [Int]
    let vmin: Int
    let vmax: Int
    let isEvenSizedCube: Bool
}

struct Coords {
    let x: Int
    let y: Int
    let z: Int
    init(_ x: Int, _ y: Int, _ z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

func getCubeDimensions(cubeSize: Int) -> CubeDimensions {
    let isEvenSizedCube = cubeSize % 2 == 0
    let halfCubeSize = cubeSize / 2
    let values = (0..<cubeSize)
        .map { v in v - halfCubeSize }
        .map { v in isEvenSizedCube && v >= 0 ? v + 1 : v }
    let vmin = values.min()!
    let vmax = values.max()!
    return CubeDimensions(values: values,
                          vmin: vmin,
                          vmax: vmax,
                          isEvenSizedCube: isEvenSizedCube)
}

func allCoords(cubeSize: Int) -> [Coords] {
    let cubeDimensions = getCubeDimensions(cubeSize: cubeSize)
    func isFace(_ v: Int) -> Bool { return v == cubeDimensions.vmin || v == cubeDimensions.vmax }
    var allCoordsList = [Coords]()
    for x in cubeDimensions.values {
        for y in cubeDimensions.values {
            for z in cubeDimensions.values {
                if isFace(x) || isFace(y) || isFace(z) {
                    allCoordsList.append(Coords(x, y, z))
                }
            }
        }
    }
    return allCoordsList
}

func pitchSliceCoordsList(allCoordsList: [Coords], x: Int) -> [Coords] {
    return allCoordsList.filter { coords in coords.x == x }
}

func yawSliceCoordsList(allCoordsList: [Coords], y: Int) -> [Coords] {
    return allCoordsList.filter { coords in coords.y == y }
}

func rollSliceCoordsList(allCoordsList: [Coords], z: Int) -> [Coords] {
    return allCoordsList.filter { coords in coords.z == z }
}
