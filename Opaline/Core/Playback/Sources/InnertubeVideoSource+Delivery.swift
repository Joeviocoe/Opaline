import Foundation
import QuartzCore

// MARK: - Streaming the bytes

extension InnertubeVideoSource {
    /// Lets go of the active delivery — for SABR that takes down its session
    /// and loopback server, which otherwise live as long as the source does.
    func releaseDelivery() {
        delivery = nil
    }

    /// Builds playback through the delivery this source was created with.
    ///
    /// There is no second choice here on purpose: a source is one client and
    /// one delivery, and moving on after a failure is the chain's job. That
    /// keeps the order of attempts in the user's settings instead of in a
    /// heuristic nobody can see.
    func deliver(
        _ request: DeliveryRequest,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard deliveryFactory.canServe(request.info) else {
            AppLog.player(
                "delivery \(deliveryFactory.label): response carries nothing it can serve"
            )
            completion(.failure(Self.deliveryUnavailableError))
            return
        }
        let stream = deliveryFactory.make(
            client: client, transport: transport, poToken: sabrPoToken
        )
        delivery = stream
        let started = CACurrentMediaTime()
        stream.prepare(request) { result in
            let elapsed = (CACurrentMediaTime() - started) * 1_000
            switch result {
            case .success:
                AppLog.player(String(
                    format: "delivery %@ ready in %.0f ms", stream.label, elapsed
                ))
            case .failure(let error):
                AppLog.player(
                    "delivery \(stream.label) failed (\(error.localizedDescription))"
                )
            }
            completion(result)
        }
    }
}
