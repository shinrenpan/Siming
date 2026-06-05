import Hummingbird
import NIOCore
import Prometheus

public func addMetricsRoute(to router: Router<BasicRequestContext>, registry: PrometheusCollectorRegistry) {
    router.get("metrics") { _, _ in
        var buffer = [UInt8]()
        registry.emit(into: &buffer)
        var headers = HTTPFields()
        headers[.contentType] = "text/plain; version=0.0.4; charset=utf-8"
        return Response(
            status: .ok,
            headers: headers,
            body: ResponseBody(byteBuffer: ByteBuffer(bytes: buffer))
        )
    }
}
