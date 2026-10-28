//
//  MemoryItem.swift
//  OllamaApp
//
//  Created by maochengfang on 2026/10/28.
//  记忆数据模型 + 向量数学（纯函数，零依赖）

import Foundation

struct MemoryItem: Codable, Equatable, Identifiable {
    let id: String
    let text: String
    let embedding: [Float]
    var createdAt: Date
    var metadata: [String: String]
    
    init(id: String = UUID().uuidString, text: String, embedding: [Float], createdAt: Date = Date(), metadata: [String : String] = [:]) {
        self.id = id
        self.text = text
        self.embedding = embedding
        self.createdAt = createdAt
        self.metadata = metadata
    }
}

struct MemoryMatch: Equatable {
    let item: MemoryItem
    let similarity: Float
}


enum VectorMath {
    static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var dot: Float = 0
        var normLHS: Float = 0
        var normRHS: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            normLHS += lhs[index] * lhs[index]
            normRHS += rhs[index] * rhs[index]
        }
        let denominator = sqrt(normLHS) * sqrt(normRHS)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
}
