import Foundation
import FigmaExportCore
import Stencil
import PathKit

final public class AndroidColorExporter: AndroidExporter {

    private let output: AndroidOutput
    private let xmlOutputFileName: String

    public init(output: AndroidOutput, xmlOutputFileName: String?) {
        self.output = output
        self.xmlOutputFileName = xmlOutputFileName ?? "colors.xml"
        super.init(templatesPath: output.templatesPath)
    }
    
    public func export(colorPairs: [AssetPair<Color>]) throws -> [FileContents] {
        // Debug: Print all incoming color names
        print("--- RAW COLOR NAMES FROM FIGMA ---")
        colorPairs.forEach { print($0.light.name) }
        print("------------------------------------")

        // Filter to only keep ds_sys_ and ds_state_layers_ colors
        let filteredColorPairs = colorPairs.filter {
            let lowercasedName = $0.light.name.lowercased()
            return lowercasedName.hasPrefix("ds_sys_") || lowercasedName.hasPrefix("ds_state_layers_")
        }
        
        // Debug: Show filtering results
        let filteredOutColors = colorPairs.filter {
            let lowercasedName = $0.light.name.lowercased()
            return !(lowercasedName.hasPrefix("ds_sys_") || lowercasedName.hasPrefix("ds_state_layers_"))
        }
        
        print("--- FILTERED OUT COLORS ---")
        filteredOutColors.forEach { print($0.light.name) }
        print("--- KEPT COLORS (\(filteredColorPairs.count) total) ---")
        filteredColorPairs.forEach { 
            let color = $0.light
            print("\(color.name) - Alpha: \(color.alpha), ComposeHex: \(color.composeHexValue)") 
        }
        print("------------------------------------")

        // Generate XML colors file
        let lightFile = try makeColorsFileContents(colorPairs: filteredColorPairs, dark: false)
        var result = [lightFile]

        // Generate dark mode XML if needed
        if filteredColorPairs.contains(where: { $0.dark != nil }) {
            let darkFile = try makeColorsFileContents(colorPairs: filteredColorPairs, dark: true)
            result.append(darkFile)
        }

        // Generate Compose Colors.kt file
        if let packageName = output.packageName,
           let outputDirectory = output.composeOutputDirectory,
           let xmlResourcePackage = output.xmlResourcePackage {

            let composeFile = try makeComposeColorsFileContents(
                colorPairs: filteredColorPairs,
                package: packageName,
                xmlResourcePackage: xmlResourcePackage,
                outputDirectory: outputDirectory
            )
            result.append(composeFile)
        }
        
        return result
    }
    
    private func makeColorsFileContents(colorPairs: [AssetPair<Color>], dark: Bool) throws -> FileContents {
        let contents = try makeColorsContents(colorPairs, dark: dark)
        
        let directoryURL = output.xmlOutputDirectory.appendingPathComponent(dark ? "values-night" : "values")
        let fileURL = URL(string: xmlOutputFileName)!
        
        return try makeFileContents(for: contents, directory: directoryURL, file: fileURL)
    }
    
    private func makeColorsContents(_ colorPairs: [AssetPair<Color>], dark: Bool) throws -> String {
        let colors: [[String: String]] = colorPairs.map { colorPair in
            [
                "name": colorPair.light.name,
                "hex": (dark && colorPair.dark != nil) ? colorPair.dark!.hex : colorPair.light.hex
            ]
        }
        let context: [String: Any] = [
            "colors": colors
        ]
        
        let env = makeEnvironment()
        return try env.renderTemplate(name: "colors.xml.stencil", context: context)
    }
    
    private func makeComposeColorsFileContents(
        colorPairs: [AssetPair<Color>],
        package: String,
        xmlResourcePackage: String,
        outputDirectory: URL
    ) throws -> FileContents {
        let colors: [[String: String]] = colorPairs.map {
            [
                "functionName": $0.light.name.lowerCamelCased(),
                "name": $0.light.name,
                "hexValue": $0.light.composeHexValue
            ]
        }

        let context: [String: Any] = [
            "package": package,
            "xmlResourcePackage": xmlResourcePackage,
            "colors": colors
        ]

        let env = makeEnvironment()
        let string = try env.renderTemplate(name: "Colors.kt.stencil", context: context)
        
        let fileURL = URL(string: "Colors.kt")!
        return try makeFileContents(for: string, directory: outputDirectory, file: fileURL)
    }
}

private extension Color {

    func doubleToHex(_ double: Double) -> String {
        String(format: "%02X", arguments: [Int((double * 255).rounded())])
    }

    var hex: String {
        let rr = doubleToHex(red)
        let gg = doubleToHex(green)
        let bb = doubleToHex(blue)
        var result = "#\(rr)\(gg)\(bb)"
        if alpha != 1.0 {
            let aa = doubleToHex(alpha)
            result = "#\(aa)\(rr)\(gg)\(bb)"
        }
        return result
    }
    
    // Generate hex value for Jetpack Compose Color constructor
    var composeHexValue: String {
        let aa = doubleToHex(alpha)
        let rr = doubleToHex(red)
        let gg = doubleToHex(green)
        let bb = doubleToHex(blue)
        
        // Always include alpha for Jetpack Compose (ARGB format)
        return "\(aa)\(rr)\(gg)\(bb)"
    }
}
