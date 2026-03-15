import XCTest
@testable import RuWisperLib

final class GigaAMTests: XCTestCase {

    func testTranscribeAudioFile() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let audioPath = "\(home)/Developer/personal/GigaAM/mlx_convert/test_ru.wav"
        let audioURL = URL(fileURLWithPath: audioPath)

        guard FileManager.default.fileExists(atPath: audioPath) else {
            print("Test audio not found at \(audioPath), skipping")
            return
        }

        let transcriber = GigaAMTranscriber()
        let t0 = CFAbsoluteTimeGetCurrent()
        try transcriber.loadModel()
        let loadTime = CFAbsoluteTimeGetCurrent() - t0
        print("Model loaded in \(String(format: "%.2f", loadTime))s")

        let t1 = CFAbsoluteTimeGetCurrent()
        let text = try transcriber.transcribe(audioURL: audioURL)
        let transcribeTime = CFAbsoluteTimeGetCurrent() - t1
        print("Transcribed in \(String(format: "%.2f", transcribeTime))s")
        print("Result: \(text)")

        XCTAssertFalse(text.isEmpty, "Transcription should not be empty")
        XCTAssertTrue(text.contains("лукоморья") || text.contains("дуб"), "Should contain Russian text from the test audio")
    }
}
