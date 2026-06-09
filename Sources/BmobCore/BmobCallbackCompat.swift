import Foundation

// MARK: - BmobCallbackCompat

/// async/await → 回调 Closure 兼容包装
/// 为所有主要的 async API 提供 @MainActor 回调版本
@MainActor
public enum BmobCallbackCompat {

    /// Result 类型别名
    public typealias Completion<T> = (Result<T, Error>) -> Void

    /// 通用 async → 回调桥接
    public static func bridge<T>(_ asyncBlock: @escaping () async throws -> T, completion: @escaping Completion<T>) {
        Task { @MainActor in
            do {
                let result = try await asyncBlock()
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// 通用 async → 回调桥接（无返回值）
    public static func bridgeVoid(_ asyncBlock: @escaping () async throws -> Void, completion: @escaping Completion<Void>) {
        Task { @MainActor in
            do {
                try await asyncBlock()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
