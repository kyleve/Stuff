import type { AtlasScreen } from "./manifest.ts";
import type { Panel, ViewMode } from "./session.ts";

/** Navigation commands supplied by the application owner. */
export interface Actions {
    chooseProfile: (profile: string) => void;
    openPanel: (panel: Panel, triggerID: string) => void;
    chooseView: (view: ViewMode) => void;
    chooseVariant: (screen: AtlasScreen, variantID: string, updateHistory?: boolean) => void;
    openScreen: (screenID: string | null | undefined, preserveVariant?: boolean) => void;
    closeInspector: () => void;
    neighboringScreen: (offset: number) => AtlasScreen | null;
    closePanel: () => void;
    renderOrNavigate: () => void;
    render: () => void;
}
