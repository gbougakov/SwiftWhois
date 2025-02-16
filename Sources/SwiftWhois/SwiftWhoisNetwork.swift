//
//  SwiftWhoisNetwork.swift
//
//
//  Created by isaced on 2023/12/20.
//

import Foundation
import Network

struct SwiftWhoisNetwork {
    static func whoisQuery(domain: String, server: String) async throws -> String? {
        let port: NWEndpoint.Port = 43
        let connection = NWConnection(host: NWEndpoint.Host(server), port: port, using: .tcp)
        
        let res = try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    sendWhoisQuery(connection: connection, domain: domain, continuation: continuation)
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
        
        connection.cancel()
        
        return res
    }

    static func sendWhoisQuery(connection: NWConnection, domain: String, continuation: CheckedContinuation<String, Error>) {
        let query = domain + "\r\n"
        guard let data = query.data(using: .utf8) else {
            continuation.resume(throwing: NSError(domain: "Invalid String Encoding", code: -1, userInfo: nil))
            return
        }
        
        connection.send(content: data, completion: .contentProcessed({ sendError in
            if let error = sendError {
                continuation.resume(throwing: error)
            } else {
                receiveWhoisResponse(connection: connection, continuation: continuation)
            }
        }))
    }

    static func receiveWhoisResponse(connection: NWConnection, continuation: CheckedContinuation<String, Error>) {
        var accumulatedData = Data()
        
        func receiveNextChunk() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, receiveError in
                if let data = data, !data.isEmpty {
                    accumulatedData.append(data)
                    
                    // Continue receiving if not complete
                    if !isComplete {
                        receiveNextChunk()
                    } else {
                        // Process complete response
                        let response = String(data: accumulatedData, encoding: .utf8) ?? ""
                        continuation.resume(returning: response)
                        connection.cancel()
                    }
                } else if let error = receiveError {
                    continuation.resume(throwing: error)
                    connection.cancel()
                } else if isComplete {
                    // Process any accumulated data before closing
                    if !accumulatedData.isEmpty {
                        let response = String(data: accumulatedData, encoding: .utf8) ?? ""
                        continuation.resume(returning: response)
                    } else {
                        continuation.resume(throwing: NSError(domain: "Connection closed by remote host", code: -1, userInfo: nil))
                    }
                    connection.cancel()
                }
            }
        }
        
        receiveNextChunk()
    }
}
