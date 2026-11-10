//
//  AudioTools.swift
//  ChatUIKit
//
//  Created by 朱继超 on 2023/11/29.
//

import AVFoundation

@objc open class AudioTools: NSObject {
    
    @objc public static let shared = AudioTools()
        
    private var stopPlayClosure: ((String) -> Void)?
    
    private var audioRecorder: AVAudioRecorder?
    
    private var audioPlayer: AVAudioPlayer?
    
    public private(set) var audioFileURL: URL?
    
    @objc public func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            let documentsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let chatFilesPath = documentsDirectory.appendingPathComponent("EaseChatUIKit/chatfiles/")
            
            if !FileManager.default.fileExists(atPath: chatFilesPath.path) {
                try FileManager.default.createDirectory(at: chatFilesPath, withIntermediateDirectories: true, attributes: nil)
            }
            
            let audioFilename = chatFilesPath.appendingPathComponent("\(Int(Date().timeIntervalSince1970*1000)).wav")
            self.audioFileURL = audioFilename
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 8000.0,
                AVLinearPCMBitDepthKey: 16,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ] as [String : Any]
            
            self.audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            self.audioRecorder?.delegate = self
            self.audioRecorder?.prepareToRecord()
            self.audioRecorder?.record()
        } catch {
            consoleLogInfo("Failed to start recording: \(error.localizedDescription)", type: .error)
        }
    }
    
    @objc public func stopRecording() {
        self.audioRecorder?.stop()
        self.audioRecorder = nil
    }
    
    @objc public func playRecording(stopPlay: @escaping () -> Void) {
        guard let url = self.audioFileURL else { return }
        if AudioTools.canPlay(url: url) {
            self.playFile(at: url.path) { _ in stopPlay() }
        } else {
            if let path = MediaConvertor.convertAMRToWAV(url: url).1 {
                self.audioFileURL = URL(fileURLWithPath: path)
                self.playRecording(stopPlay: stopPlay)
            }
        }
        
    }
    
    @objc public func playRecording(path: String,stopPlay: @escaping (String) -> Void) {
        self.playFile(at: path, onStop: stopPlay)
    }

    @discardableResult
    func playFile(at path: String, onStop: @escaping (String) -> Void) -> Bool {
        self.stopPlaying()
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.delegate = self
            guard player.play() else { return false }
            self.audioPlayer = player
            self.stopPlayClosure = onStop
            return true
        } catch {
            consoleLogInfo("Failed to play recording: \(error.localizedDescription)", type: .error)
            return false
        }
    }
    
    @objc static public func canPlay(url: URL) -> Bool {
        if url.path.hasSuffix(".amr") {
            return false
        } else {
            guard let data = try? Data(contentsOf: url)  else { return false }
            let dataString = String(data: data, encoding: .ascii) ?? ""
            if dataString.starts(with: "#!AMR\n") || dataString.starts(with: "#!AMR-WB\n") {
                return false
            } else {
                do {
                    _ = try AVAudioPlayer(contentsOf: url)
                    return true
                } catch {
                    return false
                }
            }
        }
    }
    
    @objc public func stopPlaying() {
        let player = self.audioPlayer
        let onStop = self.stopPlayClosure
        self.audioPlayer = nil
        self.stopPlayClosure = nil
        player?.stop()
        if let player { onStop?(player.url?.path ?? "") }
    }
    
}

extension AudioTools: AVAudioPlayerDelegate,AVAudioRecorderDelegate {
    
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.audioPlayer else { return }
        if !flag { consoleLogInfo("play audio error", type: .error) }
        self.stopPlaying()
    }
    
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            let tuple = MediaConvertor.convertWAVToAMR(url: recorder.url)
            if let path = tuple.1 {
                AudioTools.shared.audioFileURL = URL(fileURLWithPath: path)
            }
        } else {
            consoleLogInfo("record audio error", type: .error)
        }
    }
}

