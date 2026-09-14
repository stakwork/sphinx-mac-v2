export function requireAuthoring(services) {
    const authoring = services?.authoring;
    if (!authoring) {
        throw new Error("meta/* steps require the authoring capability (ctx.services.authoring). " +
            "The standard strut server provides it automatically; embedders can inject one " +
            "via buildAuthoringCapability (import from 'strut').");
    }
    return authoring;
}
//# sourceMappingURL=_shared.js.map