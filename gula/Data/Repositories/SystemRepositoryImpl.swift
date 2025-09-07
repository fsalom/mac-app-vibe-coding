import Foundation
#if os(macOS)
import AppKit
#endif

class SystemRepositoryImpl: SystemRepositoryProtocol {
    func checkCommandExists(_ command: String) async throws -> Bool {
        #if os(macOS)
        do {
            print("🔧 Executing command: \(command)")
            let result = try await executeCommand(command)
            let output = result.trimmingCharacters(in: .whitespacesAndNewlines)
            print("📤 Command '\(command)' output: '\(output)'")
            
            // For test commands, success (exit code 0) means the file exists
            // The output will be empty but that's expected for test commands
            let exists = true // If we reach here, the command succeeded (exit code 0)
            print("🔍 Command exists result: \(exists)")
            return exists
        } catch {
            print("❌ Command '\(command)' failed with error: \(error)")
            // For test commands, failure means the file doesn't exist
            return false
        }
        #else
        // En iOS/simulador, simulamos el comportamiento para testing
        #if DEBUG
        // En debug en iOS, simulamos que las dependencias están instaladas
        print("DEBUG iOS: Simulating command check for: \(command)")
        return true
        #else
        return command.contains("brew") || command.contains("gula")
        #endif
        #endif
    }
    
    func executeCommand(_ command: String) async throws -> String {
        #if os(macOS)
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.launchPath = "/bin/bash"
            process.arguments = ["-c", command]
            
            // Set up the environment with proper PATH including shell initialization
            var environment = ProcessInfo.processInfo.environment
            let commonPaths = [
                "/usr/local/bin",
                "/opt/homebrew/bin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin"
            ]
            let currentPath = environment["PATH"] ?? ""
            let fullPath = (commonPaths + [currentPath]).joined(separator: ":")
            environment["PATH"] = fullPath
            
            // Also source shell profile and add Homebrew paths explicitly
            let enhancedCommand = """
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH";
            source ~/.bash_profile 2>/dev/null || source ~/.zshrc 2>/dev/null || true;
            eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)";
            \(command)
            """
            process.arguments = ["-c", enhancedCommand]
            process.environment = environment
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            print("🚀 Executing: \(enhancedCommand) with PATH: \(fullPath)")
            
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                print("📋 Process finished with status: \(process.terminationStatus)")
                print("📋 Output: '\(output)'")
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let error = NSError(
                        domain: "SystemRepository",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Command failed: \(output)"]
                    )
                    continuation.resume(throwing: error)
                }
            }
            
            do {
                try process.run()
            } catch {
                print("❌ Failed to start process: \(error)")
                continuation.resume(throwing: error)
            }
        }
        #else
        // En iOS, simulamos la ejecución de comandos
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 segundo
        return "Simulated command execution on iOS"
        #endif
    }
    
    @MainActor
    func executeCommandInTerminal(_ command: String) async throws -> String {
        #if os(macOS)
        return try await withCheckedThrowingContinuation { continuation in
            let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\"")
            
            let appleScript = """
            tell application "Terminal"
                activate
                set currentTab to do script "\(escapedCommand)"
                
                -- Wait for the command to complete
                repeat
                    delay 3
                    if not busy of currentTab then exit repeat
                end repeat
                
                -- Get the output
                set commandOutput to contents of currentTab
                
                -- Close the tab gracefully
                delay 1
                try
                    set windowOfTab to (get window of currentTab)
                    if (count of tabs of windowOfTab) > 1 then
                        -- Multiple tabs, just close this tab
                        close currentTab
                    else
                        -- Only tab, close the window
                        close windowOfTab
                    end if
                on error errorMessage
                    -- If closing fails, try alternative approaches
                    try
                        -- Try to quit current tab's process first
                        do script "exit" in currentTab
                        delay 0.5
                        close currentTab
                    on error
                        -- Last resort: force close if it's the only window
                        try
                            if (count of windows of application "Terminal") = 1 and (count of tabs of (get window of currentTab)) = 1 then
                                quit application "Terminal"
                            end if
                        end try
                    end try
                end try
                
                return commandOutput
            end tell
            """
            
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", appleScript]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                print("📋 AppleScript finished with status: \(process.terminationStatus)")
                print("📋 Terminal output: '\(output)'")
                
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let error = NSError(
                        domain: "SystemRepository",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "Terminal execution failed: \(output)"]
                    )
                    continuation.resume(throwing: error)
                }
            }
            
            do {
                try task.run()
            } catch {
                print("❌ Failed to execute AppleScript: \(error)")
                continuation.resume(throwing: error)
            }
        }
        #else
        throw NSError(domain: "SystemRepository", code: -1, userInfo: [NSLocalizedDescriptionKey: "Terminal execution not supported on this platform"])
        #endif
    }
}