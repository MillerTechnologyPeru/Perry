import PackagePlugin

/// Generates a provider module's perry_provider_startup and
/// perry_provider_symbol from its @ObjCClass, @ObjCCategory and
/// @ObjCConstants declarations, with PerryProviderGenerator.
@main
struct PerryProviderPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let module = target as? SourceModuleTarget else { return [] }
        let sources = module.sourceFiles(withSuffix: "swift").map(\.url)
        let output = context.pluginWorkDirectoryURL.appending(path: "PerryProvider.generated.swift")
        return [
            .buildCommand(
                displayName: "Generating Perry provider entry points for \(target.name)",
                executable: try context.tool(named: "PerryProviderGenerator").url,
                arguments: [output.path] + sources.map(\.path),
                inputFiles: sources,
                outputFiles: [output]),
        ]
    }
}
