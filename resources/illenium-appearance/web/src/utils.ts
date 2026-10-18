export const getCdnUrl = (type: 'component' | 'prop', id: number, drawable: number, texture: number, gender: 'male' | 'female' = 'male') => {
  const componentMap: Record<number, { name: string, hasGender: boolean }> = {
    0: { name: 'head', hasGender: true },
    1: { name: 'masks', hasGender: false },
    2: { name: 'hair', hasGender: true },
    3: { name: 'torsos', hasGender: true },
    4: { name: 'legs', hasGender: true },
    5: { name: 'bags', hasGender: false },
    6: { name: 'shoes', hasGender: true },
    7: { name: 'accessories', hasGender: true },
    8: { name: 'undershirts', hasGender: true },
    9: { name: 'bodyarmors', hasGender: true },
    10: { name: 'decals', hasGender: true },
    11: { name: 'tops', hasGender: true }
  };

  const propMap: Record<number, { name: string, hasGender: boolean }> = {
    0: { name: 'hats', hasGender: true },
    1: { name: 'glasses', hasGender: true },
    2: { name: 'ears', hasGender: true },
    6: { name: 'watches', hasGender: true },
    7: { name: 'bracelets', hasGender: true }
  };

  const map = type === 'component' ? componentMap : propMap;
  const category = map[id];

  if (!category) {
    return './files/faces/SKEL_ROOT.000.webp';
  }

  const genderPath = category.hasGender ? `/${gender}` : '';
  return `https://cdn.jsdelivr.net/gh/ShortByte/GTA5-Cloth-Assets/assets/${category.name}${genderPath}/${drawable}/${texture}.webp`;
};

// Where an item's thumbnail may be, the likeliest first. This server's own come first: the resource's thumbs/
// folder (see its README), shot off the game with fivem-greenscreener - every slot, addon clothes too, numbered as
// this server numbers them (it leaves the texture off the name of an item's first one). Then the public set, which
// has no hats, glasses, ears, watches, bracelets or bags and no addon clothes.
export const getClothImageCandidates = (type: 'component' | 'prop', id: number, drawable: number, texture: number, gender: 'male' | 'female' = 'male'): string[] => {
  const sex = gender === 'female' ? 'female' : 'male';
  const item = `../../thumbs/${sex}_${type === 'prop' ? 'prop_' : ''}${id}_${drawable}`;
  // (.webp is what _tools/cloth_thumbs draws, .png what the greenscreener shoots)
  const own = `${item}${texture ? `_${texture}` : ''}`;
  const urls = [`${own}.webp`, `${own}.png`];
  const cdn = getCdnUrl(type, id, drawable, texture, sex);
  if (cdn.startsWith('https://')) urls.push(cdn);
  // (last, the picture of the item's first texture: the shape is right if the colour is not)
  if (texture) urls.push(`${item}.webp`, `${item}.png`);
  return urls;
};

// A tattoo's picture in the resource's thumbs/ folder (_tools/cloth_thumbs tattoos: drawn on a clay mannequin where the
// game puts it), named by the two names AddPedDecorationFromHashes takes - its collection and the gender's preset - in
// lower case. null for a tattoo the gender has no preset of.
export const getTattooImage = (
  tattoo: { collection?: string; hashMale?: string; hashFemale?: string },
  gender: 'male' | 'female' = 'male',
): string | null => {
  const preset = gender === 'female' ? tattoo.hashFemale : tattoo.hashMale;
  if (!tattoo.collection || !preset) return null;
  return `../../thumbs/${`${gender}_tattoo_${tattoo.collection}_${preset}`.toLowerCase()}.webp`;
};

const DOCS = "https://docs.fivem.net";
const GTAHASH_PED_THUMB = "https://gtahash.com/models/peds/thumbs";

const resolvedImageCache = new Map<string, string>();

export function getCachedAssetImage(model: string, kind: "prop" | "ped" = "ped"): string | null {
  return resolvedImageCache.get(`${kind}:${model.toLowerCase()}`) || null;
}

export function setCachedAssetImage(model: string, kind: "prop" | "ped", url: string) {
  if (!model || !url || url.startsWith("data:")) return;
  resolvedImageCache.set(`${kind}:${model.toLowerCase()}`, url);
}

export function getPedImageCandidates(model: string): string[] {
  const name = model.toLowerCase().trim();
  const cached = getCachedAssetImage(name, "ped");
  const urls = [
    `${GTAHASH_PED_THUMB}/${name}.webp`,
    `${GTAHASH_PED_THUMB}/${name}.png`,
    `${DOCS}/peds/${name}.webp`,
    `${DOCS}/peds/${name}.png`,
  ];
  if (cached) return [cached, ...urls.filter((u) => u !== cached)];
  return urls;
}

function hashHue(input: string): number {
  let h = 0;
  for (let i = 0; i < input.length; i += 1) {
    h = (h * 31 + input.charCodeAt(i)) >>> 0;
  }
  return h % 360;
}

function modelInitials(model: string): string {
  const parts = model
    .toLowerCase()
    .replace(/^a_[c|f|m]_[m|y|s]_/, "")
    .replace(/^mp_[m|f]_/, "")
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
  if (parts.length >= 2) {
    const a = parts[parts.length - 2][0] || "";
    const b = parts[parts.length - 1][0] || "";
    return `${a}${b}`.toUpperCase() || "PD";
  }
  const clean = (parts[0] || "pd").replace(/[^a-z0-9]/g, "");
  return (clean.slice(0, 2) || "PD").toUpperCase();
}

export function getModelThumbDataUri(model: string, kind: "prop" | "ped" = "ped"): string {
  const initials = modelInitials(model);
  const hue = hashHue(model.toLowerCase());
  const accent = kind === "ped" ? "#00f0ff" : `hsl(${hue} 70% 55%)`;
  const label = initials.replace(/&/g, "").slice(0, 2);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#0e1218"/>
      <stop offset="100%" stop-color="#141a22"/>
    </linearGradient>
  </defs>
  <rect width="256" height="256" fill="url(#g)"/>
  <rect x="18" y="18" width="220" height="220" fill="none" stroke="${accent}" stroke-opacity="0.35" stroke-width="3"/>
  <text x="128" y="148" text-anchor="middle" font-family="Arial,sans-serif" font-size="72" font-weight="700" fill="${accent}">${label}</text>
</svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}
