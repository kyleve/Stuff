/** URL state is the durable selection. Defaults omitted from a URL must reset on Back. */
interface NavigationScreen {
    id: string;
    variants: { id: string }[];
}

interface NavigationCatalog {
    screens: NavigationScreen[];
    profiles: { id: string }[];
}

export interface Selection {
    view: 'canvas' | 'list';
    profile: string;
    screen: string | null;
    variants: Map<string, string>;
}

export function readSelection(hash: string, catalog: NavigationCatalog): Selection {
    const values = new URLSearchParams(hash.replace(/^#/, ''));
    const view = values.get('view') === 'list' ? 'list' : 'canvas';
    const profile = catalog.profiles.find(profile => profile.id === values.get('profile'))?.id
        ?? catalog.profiles[0].id;
    const screen = catalog.screens.find(screen => screen.id === values.get('screen'))?.id ?? null;
    const variants = new Map(catalog.screens.map(item => {
        const requested = item.id === screen ? values.get('variant') : values.get('state.' + item.id);
        return [item.id, item.variants.find(variant => variant.id === requested)?.id ?? item.variants[0].id];
    }));
    return { view, profile, screen, variants };
}

export function selectionHash(selection: Selection, catalog: NavigationCatalog): string {
    const values = new URLSearchParams();
    values.set('view', selection.view);
    values.set('profile', selection.profile);
    for (const screen of catalog.screens) {
        const variant = selection.variants.get(screen.id);
        if (variant && variant !== screen.variants[0]?.id) values.set('state.' + screen.id, variant);
    }
    if (selection.screen) {
        values.set('screen', selection.screen);
        values.set('variant', selection.variants.get(selection.screen)!);
    }
    return '#' + values.toString();
}
