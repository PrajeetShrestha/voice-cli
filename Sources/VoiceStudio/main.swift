import Foundation
import AVFoundation
import Darwin

func problem(_ text: String) -> NSError { NSError(domain: "VoiceStudio", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
#if SWIFT_PACKAGE
let htmlURL = Bundle.module.url(forResource: "index", withExtension: "html")!
#else
let htmlURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("index.html")
#endif
let fm = FileManager.default
let token = UUID().uuidString + UUID().uuidString
let session = fm.temporaryDirectory.appendingPathComponent("voice-studio-" + UUID().uuidString)
try fm.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let stateLock = NSLock()
var busy = false
var outputs = [String]()
let ffmpeg: String? = ((ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":") + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]).filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0).appendingPathComponent("ffmpeg").path }.first { fm.isExecutableFile(atPath: $0) }

func run(_ path: String, _ args: [String], timeout: TimeInterval = 30) throws -> String {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    let log = session.appendingPathComponent(UUID().uuidString + ".log")
    fm.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close(); try? fm.removeItem(at: log) }
    p.standardOutput = handle; p.standardError = handle; p.standardInput = FileHandle.nullDevice
    try p.run()
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if p.isRunning { p.terminate(); Thread.sleep(forTimeInterval: 0.2); if p.isRunning { kill(p.processIdentifier, SIGKILL) }; p.waitUntilExit(); throw problem("Encoder timed out. Try a shorter passage.") }
    p.waitUntilExit()
    let result = String(data: (try? Data(contentsOf: log)) ?? Data(), encoding: .utf8) ?? ""
    guard p.terminationStatus == 0 else { throw problem("Command failed: " + String(result.prefix(1500))) }
    return result
}
let encoderReady: Bool = ffmpeg.flatMap { try? run($0, ["-hide_banner", "-encoders"]) }?.contains("libmp3lame") == true
func diskFree() -> Int64 { ((try? fm.attributesOfFileSystem(forPath: session.path)[.systemFreeSize]) as? NSNumber)?.int64Value ?? 0 }
let installedVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.identifier.hasPrefix("com.apple.siri.natural.") }
func voiceName(_ voice: AVSpeechSynthesisVoice) -> String { voice.identifier == "com.apple.siri.natural.Nora" ? "\(voice.name) (Siri Nora)" : voice.name }
func voices() -> [[String: String]] { installedVoices.sorted { ($0.language, $0.name) < ($1.language, $1.name) }.map { ["id": $0.identifier, "name": voiceName($0), "language": $0.language, "quality": $0.quality == .premium ? "Premium" : ($0.quality == .enhanced ? "Enhanced" : "Standard")] } }
func specs() -> [String: Any] {
    var blockers = [String]()
    if !encoderReady { blockers.append("ffmpeg with the libmp3lame encoder is required. Install ffmpeg yourself (for example, brew install ffmpeg if you already use Homebrew), then restart this CLI.") }
    if voices().isEmpty { blockers.append("No installed Siri natural voices are exposed in this launch mode. Start with ./run.sh in Terminal. If still empty, choose and download a Siri voice in System Settings → Siri (or Apple Intelligence & Siri), then restart. Standard and novelty voices are intentionally hidden.") }
    if diskFree() < 256 * 1024 * 1024 { blockers.append("Less than 256 MiB is free on the temporary volume. Free space before generating. This is this app's safety reserve, not an Apple hardware minimum.") }
    var uts = utsname(); uname(&uts)
    let arch = withUnsafePointer(to: &uts.machine) { ptr in ptr.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
    return ["os": ProcessInfo.processInfo.operatingSystemVersionString, "architecture": arch, "cores": ProcessInfo.processInfo.activeProcessorCount, "memoryBytes": ProcessInfo.processInfo.physicalMemory, "diskFreeBytes": diskFree(), "ffmpeg": ffmpeg ?? "Not found", "encoderReady": encoderReady, "blockers": blockers, "ready": blockers.isEmpty, "requirements": ["macOS 13 or newer; Intel or Apple silicon", "At least one installed Siri natural voice", "ffmpeg with libmp3lame for MP3 encoding", "256 MiB free temporary space safety reserve", "No GPU, API key, or model download required", "No extra RAM minimum imposed; long passages use more time and disk"]]
}
// Speech starts and completes on the main run loop. PCM writes are lock-protected.
// Do not spin a nested run loop inside a main-queue block: delegate delivery can stall.
final class Renderer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    let synth = AVSpeechSynthesizer(); let lock = NSLock()
    var file: AVAudioFile?; var done = false; var error: Error?; var frames: Int64 = 0
    var timer: Timer?; var completion: ((Error?) -> Void)?
    override init() { super.init(); synth.delegate = self }
    func finish(_ failure: Error? = nil) {
        lock.lock()
        guard !done else { lock.unlock(); return }
        done = true; file = nil
        let result = failure ?? error ?? (frames == 0 ? problem("This voice produced no audio. Some Siri voices cannot export audio; try another installed natural Siri voice. No substitute voice was used.") : nil)
        lock.unlock()
        timer?.invalidate(); timer = nil
        let callback = completion; completion = nil; callback?(result)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { finish() }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { finish(problem("Speech synthesis was cancelled by macOS. Try another voice, or launch with ./run.sh in Terminal to allow access to installed speech assets.")) }
    func render(text: String, voice: AVSpeechSynthesisVoice, rate: Float, to url: URL, completion: @escaping (Error?) -> Void) {
        self.completion = completion
        let u = AVSpeechUtterance(string: text); u.voice = voice; u.rate = rate
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [self] _ in
            finish(problem("Voice timed out after five minutes. Try shorter text or another installed voice."))
            synth.stopSpeaking(at: .immediate)
        }
        synth.write(u) { [self] buffer in
            lock.lock(); defer { lock.unlock() }
            guard !done, error == nil, let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else { return }
            do {
                if file == nil { file = try AVAudioFile(forWriting: url, settings: pcm.format.settings, commonFormat: pcm.format.commonFormat, interleaved: pcm.format.isInterleaved) }
                try file!.write(from: pcm); frames += Int64(pcm.frameLength)
            } catch {
                self.error = error
                DispatchQueue.main.async { [self] in finish(error); synth.stopSpeaking(at: .immediate) }
            }
        }
    }
}

struct Request { let method: String; let path: String; let headers: [String: String]; let body: Data }
func readRequest(_ fd: Int32) throws -> Request {
    var data = Data(); var buf = [UInt8](repeating: 0, count: 8192)
    let end = Date().addingTimeInterval(20)
    while Date() < end {
        let n = recv(fd, &buf, buf.count, 0); guard n > 0 else { throw problem("Incomplete HTTP request") }
        data.append(contentsOf: buf.prefix(n))
        guard data.count <= 80_000 else { throw problem("Request too large") }
        if let range = data.range(of: Data("\r\n\r\n".utf8)) {
            guard range.lowerBound < 8192, let head = String(data: data[..<range.lowerBound], encoding: .utf8) else { throw problem("Invalid headers") }
            let lines = head.components(separatedBy: "\r\n"); let first = lines[0].split(separator: " ")
            guard first.count == 3, first[2] == "HTTP/1.1" || first[2] == "HTTP/1.0" else { throw problem("Invalid request") }
            var headers = [String: String]()
            for line in lines.dropFirst() {
                guard let i = line.firstIndex(of: ":") else { throw problem("Invalid header") }
                let key = line[..<i].lowercased(); guard headers[key] == nil else { throw problem("Duplicate header") }
                headers[key] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
            }
            guard headers["transfer-encoding"] == nil else { throw problem("Chunked requests are not supported") }
            let count = Int(headers["content-length"] ?? "0") ?? -1
            guard (0...65_536).contains(count) else { throw problem("Invalid body length") }
            if data.count >= range.upperBound + count { return Request(method: String(first[0]), path: String(first[1]), headers: headers, body: data.subdata(in: range.upperBound..<(range.upperBound + count))) }
        } else if data.count > 8192 { throw problem("Headers too large") }
    }
    throw problem("Request timed out")
}
func respond(_ fd: Int32, _ code: Int, _ type: String, _ body: Data, extra: String = "") {
    let reason = [200:"OK",400:"Bad Request",403:"Forbidden",404:"Not Found",409:"Conflict",422:"Unprocessable Content",503:"Service Unavailable"][code] ?? "Error"
    let head = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; media-src blob:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\(extra)\r\n"
    let full = Data(head.utf8) + body
    full.withUnsafeBytes { bytes in var sent = 0; while sent < bytes.count { let n = send(fd, bytes.baseAddress!.advanced(by: sent), bytes.count - sent, 0); if n <= 0 { break }; sent += n } }
}
func json(_ fd: Int32, _ code: Int, _ value: [String: Any]) { respond(fd, code, "application/json", (try? JSONSerialization.data(withJSONObject: value)) ?? Data()) }
let socketFD = socket(AF_INET, SOCK_STREAM, 0)
guard socketFD >= 0 else { throw problem("Could not create local socket") }
var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET); address.sin_port = 0; address.sin_addr.s_addr = inet_addr("127.0.0.1")
let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
guard bound == 0, listen(socketFD, 16) == 0 else { throw problem("Could not listen on loopback") }
var length = socklen_t(MemoryLayout<sockaddr_in>.size)
_ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &length) } }
let port = UInt16(bigEndian: address.sin_port)
let origin = "http://127.0.0.1:\(port)"
func handle(_ fd: Int32) {
    defer { close(fd) }
    do {
        let r = try readRequest(fd)
        guard r.headers["host"] == "127.0.0.1:\(port)", r.headers["origin"] == nil || r.headers["origin"] == origin else { json(fd, 403, ["error":"Untrusted host or origin"]); return }
        if r.path == "/" && r.method == "GET" { respond(fd, 200, "text/html; charset=utf-8", try Data(contentsOf: htmlURL)); return }
        guard r.headers["authorization"] == "Bearer " + token else { json(fd, 403, ["error":"Session expired. Open the URL printed by the CLI."]); return }
        if r.path == "/api/status" && r.method == "GET" { stateLock.lock(); let b = busy; stateLock.unlock(); json(fd, 200, ["specs":specs(), "voices":voices(), "busy":b]); return }
        if r.path.hasPrefix("/api/audio/") && r.method == "GET" {
            let id = String(r.path.dropFirst("/api/audio/".count)); stateLock.lock(); let exists = outputs.contains(id); stateLock.unlock()
            guard exists else { json(fd, 404, ["error":"Audio expired or not found"]); return }
            respond(fd, 200, "audio/mpeg", try Data(contentsOf: session.appendingPathComponent(id + ".mp3")), extra: "Content-Disposition: attachment; filename=\"voice-studio.mp3\"\r\n"); return
        }
        guard r.path == "/api/generate", r.method == "POST" else { json(fd, 404, ["error":"Not found"]); return }
        guard r.headers["content-type"]?.hasPrefix("application/json") == true, let obj = try JSONSerialization.jsonObject(with: r.body) as? [String: Any], let text = obj["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 10_000, let voiceID = obj["voice"] as? String, let voice = installedVoices.first(where: {$0.identifier == voiceID}), let rate = obj["rate"] as? Double, rate.isFinite, (0.2...0.65).contains(rate) else { json(fd, 400, ["error":"Provide 1–10,000 characters, an installed voice, and a rate from 0.20–0.65."]); return }
        guard specs()["ready"] as? Bool == true, let ffmpeg else { json(fd, 503, ["error":"Requirements are unmet. Check Device readiness."]); return }
        stateLock.lock(); if busy { stateLock.unlock(); json(fd, 409, ["error":"Another generation is running. Wait for it to finish."]); return }; busy = true; stateLock.unlock()
        defer { stateLock.lock(); busy = false; stateLock.unlock() }
        let id = UUID().uuidString; let caf = session.appendingPathComponent(id + ".caf"); let mp3 = session.appendingPathComponent(id + ".mp3")
        defer { try? fm.removeItem(at: caf) }
        let done = DispatchSemaphore(value: 0); var failure: Error?
        DispatchQueue.main.async {
            let renderer = Renderer()
            renderer.render(text: text, voice: voice, rate: Float(rate), to: caf) { [renderer] error in
                _ = renderer // Retain through delegate completion.
                failure = error; done.signal()
            }
        }
        done.wait()
        if let failure { throw failure }
        do { _ = try run(ffmpeg, ["-hide_banner","-loglevel","error","-nostdin","-n","-i",caf.path,"-codec:a","libmp3lame","-q:a","2",mp3.path], timeout: 120) } catch { try? fm.removeItem(at: mp3); throw error }
        stateLock.lock(); outputs.append(id); if outputs.count > 20 { let old = outputs.removeFirst(); try? fm.removeItem(at: session.appendingPathComponent(old + ".mp3")) }; stateLock.unlock()
        json(fd, 200, ["id": id, "voice": voiceName(voice), "download": "/api/audio/" + id])
    } catch { json(fd, 422, ["error": error.localizedDescription]) }
}
signal(SIGPIPE, SIG_IGN)
signal(SIGINT, SIG_IGN); signal(SIGTERM, SIG_IGN)
let intSignal = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
let termSignal = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
for source in [intSignal, termSignal] { source.setEventHandler { close(socketFD); try? fm.removeItem(at: session); print("\nVoice Studio stopped. Temporary audio removed."); exit(0) }; source.resume() }
let slots = DispatchSemaphore(value: 8)
DispatchQueue.global().async {
    while true {
        slots.wait(); let fd = accept(socketFD, nil, nil)
        if fd < 0 { slots.signal(); continue }
        var timeout = timeval(tv_sec: 20, tv_usec: 0); setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)); setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        DispatchQueue.global().async { handle(fd); slots.signal() }
    }
}
let url = origin + "/#" + token
print("Voice Studio\nLocal only. Stop with Control-C.\nOpen: \(url)\n")
fflush(stdout)
if !CommandLine.arguments.contains("--no-open") { let open = Process(); open.executableURL = URL(fileURLWithPath: "/usr/bin/open"); open.arguments = [url]; try? open.run() }
RunLoop.main.run()
