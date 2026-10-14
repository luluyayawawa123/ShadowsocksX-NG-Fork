//
//  PACUtils.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/9.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa
import Alamofire

let OldErrorPACRulesDirPath = NSHomeDirectory() + "/.ShadowsocksX-NE/"

let PACRulesDirPath = NSHomeDirectory() + "/.ShadowsocksX-NG/"
let PACUserRuleFilePath = PACRulesDirPath + "user-rule.txt"
let PACFilePath = PACRulesDirPath + "gfwlist.js"
let GFWListFilePath = PACRulesDirPath + "gfwlist.txt"

private func decodedGFWList(_ encoded: Data) -> String? {
    guard let decoded = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
        let text = String(data: decoded, encoding: .utf8),
        text.hasPrefix("[AutoProxy") else {
        return nil
    }
    return text
}

private func gfwListModifiedDate(in text: String) -> Date? {
    guard let header = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("! Last Modified: ") }) else {
        return nil
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    return formatter.date(from: String(header.dropFirst("! Last Modified: ".count)))
}

func gfwListModifiedDate(at path: String) -> Date? {
    guard let encoded = try? Data(contentsOf: URL(fileURLWithPath: path)),
        let text = decodedGFWList(encoded) else {
        return nil
    }
    return gfwListModifiedDate(in: text)
}

func shouldInstallBundledGFWList() -> Bool {
    if !FileManager.default.fileExists(atPath: GFWListFilePath) {
        return true
    }
    guard let bundledPath = Bundle.main.path(forResource: "gfwlist", ofType: "txt"),
        let bundledDate = gfwListModifiedDate(at: bundledPath) else {
        return false
    }
    guard let localDate = gfwListModifiedDate(at: GFWListFilePath) else {
        return true
    }
    return bundledDate > localDate
}


// Use the active proxy endpoint consistently when regenerating PAC rules.
private func pacProxyDirective() -> String? {
    let defaults = UserDefaults.standard
    let useHTTP = defaults.bool(forKey: "LocalHTTPOn")
    let prefix = useHTTP ? "LocalHTTP" : "LocalSocks5"
    guard let address = defaults.string(forKey: "\(prefix).ListenAddress") else {
        return nil
    }
    let port = defaults.integer(forKey: "\(prefix).ListenPort")
    var sin6 = sockaddr_in6()
    let host = address.withCString { inet_pton(AF_INET6, $0, &sin6.sin6_addr) } == 1 ? "[\(address)]" : address
    let endpoint = "\(host):\(port)"
    return useHTTP ? "PROXY \(endpoint); DIRECT;" : "SOCKS5 \(endpoint); SOCKS \(endpoint); DIRECT;"
}

func SyncPac() {
    let defaults = UserDefaults.standard
    guard let proxy = pacProxyDirective() else { return }
    // The version also refreshes existing PAC files with the loopback bypass.
    let signature = "1|\(proxy)"
    if defaults.string(forKey: "PAC.ProxySignature") != signature ||
        !FileManager.default.fileExists(atPath: PACFilePath) || shouldInstallBundledGFWList() {
        if !GeneratePACFile() {
            NSLog("GeneratePACFile failed!")
        }
    }
}

func GeneratePACFile() -> Bool {
    let fileMgr = FileManager.default
    // Maker the dir if rulesDirPath is not exesited.
    if !fileMgr.fileExists(atPath: PACRulesDirPath) {
        do {
            if fileMgr.fileExists(atPath: OldErrorPACRulesDirPath) {
                try fileMgr.moveItem(atPath: OldErrorPACRulesDirPath, toPath: PACRulesDirPath)
            } else {
                try fileMgr.createDirectory(atPath: PACRulesDirPath
                    , withIntermediateDirectories: true, attributes: nil)
            }
        } catch {
            NSLog("Create PAC rules directory failed: \(error)")
            return false
        }
    }
    
    // Install the bundled list only when it is newer than the local list.
    if shouldInstallBundledGFWList() {
        do {
            guard let src = Bundle.main.url(forResource: "gfwlist", withExtension: "txt") else {
                return false
            }
            try Data(contentsOf: src).write(to: URL(fileURLWithPath: GFWListFilePath), options: .atomic)
        } catch {
            NSLog("Install bundled GFWList failed: \(error)")
            return false
        }
    }
    
    // If user-rule.txt is not exsited, copy from bundle
    if !fileMgr.fileExists(atPath: PACUserRuleFilePath) {
        guard let src = Bundle.main.path(forResource: "user-rule", ofType: "txt") else {
            return false
        }
        do {
            try fileMgr.copyItem(atPath: src, toPath: PACUserRuleFilePath)
        } catch {
            NSLog("Install user-rule.txt failed: \(error)")
            return false
        }
    }
    
    guard let proxy = pacProxyDirective() else {
        return false
    }

    do {
        let gfwlist = try String(contentsOfFile: GFWListFilePath, encoding: String.Encoding.utf8)
        if let data = Data(base64Encoded: gfwlist, options: .ignoreUnknownCharacters) {
            guard let str = String(data: data, encoding: .utf8), str.hasPrefix("[AutoProxy") else {
                return false
            }
            var lines = str.components(separatedBy: CharacterSet.newlines)
            
            do {
                let userRuleStr = try String(contentsOfFile: PACUserRuleFilePath, encoding: String.Encoding.utf8)
                let userRuleLines = userRuleStr.components(separatedBy: CharacterSet.newlines)
                
                lines = userRuleLines + lines.filter { (line) in
                    // ignore the rule from gwf if user provide same rule for the same url
                    var i = line.startIndex
                    while i < line.endIndex {
                        if line[i] == "@" || line[i] == "|" {
                            i = line.index(after: i)
                            continue
                        }
                        break
                    }
                    if i == line.startIndex {
                        return !userRuleLines.contains(line)
                    }
                    return !userRuleLines.contains(String(line[i...]))
                }
            } catch {
                NSLog("Read user-rule.txt failed: \(error)")
                return false
            }
            
            // Filter empty and comment lines
            lines = lines.filter({ (s: String) -> Bool in
                if s.isEmpty {
                    return false
                }
                let c = s[s.startIndex]
                if c == "!" || c == "[" {
                    return false
                }
                return true
            })
            
            do {
                // rule lines to json array
                let rulesJsonData: Data
                    = try JSONSerialization.data(withJSONObject: lines, options: .prettyPrinted)
                guard let rulesJsonStr = String(data: rulesJsonData, encoding: .utf8),
                    let jsPath = Bundle.main.url(forResource: "abp", withExtension: "js"),
                    let jsStr = try? String(contentsOf: jsPath, encoding: .utf8) else {
                    return false
                }
                
                // Get raw pac js
                var updatedJS = jsStr
                
                // Replace rules placeholder in pac js
                updatedJS = updatedJS.replacingOccurrences(of: "__RULES__"
                    , with: rulesJsonStr)
                updatedJS = updatedJS.replacingOccurrences(of: "__PROXY__", with: proxy)

                // Write the pac js to file.
                guard let pacData = updatedJS.data(using: .utf8) else {
                    return false
                }
                try pacData.write(to: URL(fileURLWithPath: PACFilePath), options: .atomic)
                UserDefaults.standard.set("1|\(proxy)", forKey: "PAC.ProxySignature")
                
                return true
            } catch {
                NSLog("Generate PAC file failed: \(error)")
            }
        }
        
    } catch {
        NSLog("Not found gfwlist.txt")
    }
    return false
}

private func gfwListDateDescription(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
    return formatter.string(from: date)
}

private func currentGFWListStatus() -> String {
    let rulesStatus: String
    if let date = gfwListModifiedDate(at: GFWListFilePath) {
        rulesStatus = String(format: "Local GFWList date: %@.".localized, gfwListDateDescription(date))
    } else {
        rulesStatus = "No valid local GFWList is available.".localized
    }
    let pacStatus = FileManager.default.fileExists(atPath: PACFilePath)
        ? "An existing PAC file is available.".localized
        : "No PAC file is available.".localized
    return rulesStatus + "\n" + pacStatus
}

private func showGFWListUpdateResult(_ title: String, detail: String, success: Bool) {
    DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = title.localized
        alert.informativeText = detail
        alert.alertStyle = success ? .informational : .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

private func showGFWListUpdateFailure(_ reason: String) {
    showGFWListUpdateResult("GFWList update failed.",
        detail: reason + "\n\n" + currentGFWListStatus(), success: false)
}

func UpdatePACFromGFWList() {
    // Make the dir if rulesDirPath is not exesited.
    if !FileManager.default.fileExists(atPath: PACRulesDirPath) {
        do {
            try FileManager.default.createDirectory(atPath: PACRulesDirPath
                , withIntermediateDirectories: true, attributes: nil)
        } catch {
            showGFWListUpdateFailure("Cannot create the rules folder. Check disk space and permissions.".localized)
            return
        }
    }
    
    guard let url = UserDefaults.standard.string(forKey: "GFWListURL"), !url.isEmpty else {
        showGFWListUpdateFailure("No GFWList download URL is configured.".localized)
        return
    }
    AF.request(url)
        .validate()
        .responseString {
            response in
            switch response.result {
            case .success(let downloaded):
                let downloadedData = Data(downloaded.utf8)
                guard let downloadedRules = decodedGFWList(downloadedData),
                    let downloadedDate = gfwListModifiedDate(in: downloadedRules) else {
                    showGFWListUpdateFailure("The download is not a valid dated GFWList. Check the configured URL.".localized)
                    return
                }
                let listURL = URL(fileURLWithPath: GFWListFilePath)
                let oldData = try? Data(contentsOf: listURL)
                let localRules = oldData.flatMap { decodedGFWList($0) }
                let localDate = localRules.flatMap { gfwListModifiedDate(in: $0) }
                let bundledDate = Bundle.main.path(forResource: "gfwlist", ofType: "txt")
                    .flatMap { gfwListModifiedDate(at: $0) }
                if let newestDate = [localDate, bundledDate].compactMap({ $0 }).max(),
                    downloadedDate < newestDate {
                    showGFWListUpdateResult("GFWList update not needed.",
                        detail: String(format: "The downloaded rules are older (%@). Your newer local or built-in rules were kept.".localized,
                            gfwListDateDescription(downloadedDate)) + "\n\n" + currentGFWListStatus(), success: true)
                    return
                }
                if downloadedRules == localRules {
                    if GeneratePACFile() {
                        showGFWListUpdateResult("GFWList is already up to date.",
                            detail: String(format: "The local rules already match the download (%@); no list update is needed. PAC was refreshed.".localized,
                                gfwListDateDescription(downloadedDate)), success: true)
                    } else {
                        showGFWListUpdateFailure("The rules match, but PAC generation failed. Check disk space, permissions, and custom rules.".localized)
                    }
                    return
                }
                do {
                    try downloadedData.write(to: listURL, options: .atomic)
                    if GeneratePACFile() {
                        showGFWListUpdateResult("GFWList and PAC updated.",
                            detail: String(format: "Downloaded and applied GFWList dated %@. Your custom rules were kept.".localized,
                                gfwListDateDescription(downloadedDate)), success: true)
                    } else {
                        do {
                            if let oldData = oldData {
                                try oldData.write(to: listURL, options: .atomic)
                            } else {
                                try FileManager.default.removeItem(at: listURL)
                            }
                            showGFWListUpdateFailure("PAC generation failed. The previous rules were restored; check disk space, permissions, and custom rules.".localized)
                        } catch {
                            showGFWListUpdateFailure("PAC generation failed, and the previous rules could not be restored. Check disk space and permissions.".localized)
                        }
                    }
                } catch {
                    showGFWListUpdateFailure("The rules could not be saved. Check disk space and permissions.".localized)
                }
            case .failure:
                if let statusCode = response.response?.statusCode {
                    showGFWListUpdateFailure(String(format: "The server returned HTTP %d. Check the download URL or try again later.".localized, statusCode))
                } else {
                    showGFWListUpdateFailure("Download failed. Check your network connection and GFWList URL, then try again.".localized)
                }
            }
        }
}
