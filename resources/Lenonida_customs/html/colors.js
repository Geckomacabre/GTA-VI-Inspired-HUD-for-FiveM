// Swatch colours for the respray menus.
// GTA paint index > hex (the game has no native that returns these).
const GTA_COLORS = {
    0: '#0d1116', 1: '#1c1d21', 2: '#32383d', 3: '#454b4f', 4: '#999da0', 5: '#c2c4c6', 6: '#979a97', 7: '#637380',
    8: '#63625c', 9: '#3c3f47', 10: '#444e54', 11: '#1d2129', 12: '#13181f', 13: '#26282a', 14: '#515554', 15: '#151921',
    16: '#1e2429', 17: '#333a3c', 18: '#8c9095', 19: '#39434d', 20: '#506272', 21: '#1e232f', 22: '#363a3f', 23: '#a0a199',
    24: '#d3d3d3', 25: '#b7bfca', 26: '#778794', 27: '#c00e1a', 28: '#da1918', 29: '#b6111b', 30: '#a51e23', 31: '#7b1a22',
    32: '#8e1b1f', 33: '#6f1818', 34: '#49111d', 35: '#b60f25', 36: '#d44a17', 37: '#c2944f', 38: '#f78616', 39: '#cf1f21',
    40: '#732021', 41: '#f27d20', 42: '#ffc91f', 43: '#9c1016', 44: '#de0f18', 45: '#8f1e17', 46: '#a94744', 47: '#b16c51',
    48: '#371c25', 49: '#132428', 50: '#122e2b', 51: '#12383c', 52: '#31423f', 53: '#155c2d', 54: '#1b6770', 55: '#66b81f',
    56: '#22383e', 57: '#1d5a3f', 58: '#2d423f', 59: '#45594b', 60: '#65867f', 61: '#222e46', 62: '#233155', 63: '#304c7e',
    64: '#47578f', 65: '#637ba7', 66: '#394762', 67: '#d6e7f1', 68: '#76afbe', 69: '#345e72', 70: '#0b9cf1', 71: '#2f2d52',
    72: '#282c4d', 73: '#2354a1', 74: '#6ea3c6', 75: '#112552', 76: '#1b203e', 77: '#275190', 78: '#608592', 79: '#2446a8',
    80: '#4271e1', 81: '#3b39e0', 82: '#1f2852', 83: '#253aa7', 84: '#1c3551', 85: '#4c5f81', 86: '#58688e', 87: '#74b5d8',
    88: '#ffcf20', 89: '#fbe212', 90: '#916532', 91: '#e0e13d', 92: '#98d223', 93: '#9b8c78', 94: '#503218', 95: '#473f2b',
    96: '#221b19', 97: '#653f23', 98: '#775c3e', 99: '#ac9975', 100: '#6c6b4b', 101: '#402e2b', 102: '#a4965f', 103: '#46231a',
    104: '#752b19', 105: '#bfae7b', 106: '#dfd5b2', 107: '#f7edd5', 108: '#3a2a1b', 109: '#785f33', 110: '#b5a079', 111: '#fffff6',
    112: '#eaeaea', 113: '#b0ab94', 114: '#453831', 115: '#2a282b', 116: '#726c57', 117: '#6a747c', 118: '#354158', 119: '#9ba0a8',
    120: '#5870a1', 121: '#eae6de', 122: '#dfddd0', 123: '#f2ad2e', 124: '#f9a458', 125: '#83c566', 126: '#f1cc40', 127: '#4cc3da',
    128: '#4e6443', 129: '#bcac8f', 130: '#f8b658', 131: '#fcf9f1', 132: '#fffffb', 133: '#81844c', 134: '#ffffff', 135: '#f21f99',
    136: '#fdd6cd', 137: '#df5891', 138: '#f6ae20', 139: '#b0ee6e', 140: '#08e9fa', 141: '#0a0c17', 142: '#0c0d18', 143: '#0e0d14',
    144: '#9f9e8a', 145: '#621276', 146: '#0b1421', 147: '#11141a', 148: '#6b1f7b', 149: '#1e1d22', 150: '#bc1917', 151: '#2d362a',
    152: '#696748', 153: '#7a6c55', 154: '#c3b492', 155: '#5a6352', 156: '#81827f', 157: '#afd6e4', 158: '#7a6440', 159: '#7f6a48',
};

// The colour words in the gen9 chameleon paint names, for their gradient swatches
const CHAMELEON_WORDS = {
    RED: '#d5202a', ORANGE: '#f07a1c', ORANG: '#f07a1c', ORAN: '#f07a1c', PURPLE: '#7a2fc0', PURP: '#7a2fc0', TURQ: '#1fc7c0',
    MAGEN: '#d425b5', CYAN: '#19c8f0', GREEN: '#2fb24c', GREE: '#2fb24c', BLACK: '#15161a', WHITE: '#f2f2f2', CREAM: '#efe3c5',
    BLUE: '#2152d9', BLU: '#2152d9', PINK: '#f065a8', YELLOW: '#f3d21f', YELL: '#f3d21f', BROW: '#7a4b22', TEAL: '#128a8a',
    BURG: '#6e1028', COPPE: '#b56a3a', COPPER: '#b56a3a', GOLD: '#d1a531', LIME: '#a4dc21', WINE: '#6a1230', BRONZE: '#93622c',
    CHAMPAGNE: '#d8c39a', GRAPHITE: '#4a4d55', OFFWHITE: '#e6e2d6', DARKTEALPEARL: '#0d5a5c', DARKBLUEPEARL: '#16286e',
    DARKBLUEPRISMA: '#16286e', DARKGREENPEARL: '#154d2a', DARKPURPLEPEARL: '#3d1764', DARKPURPPRISMA: '#3d1764',
    CHRISTMAS: '#c21f2b,#1d8a3c', SYNTHWAVE: '#ff3fb4,#5b2be0,#19c8f0', SUNSETS: '#ff7a1c,#e0245e,#5b2be0',
    BUBBLEGUM: '#ff7ac8,#7ad7ff', ELECTRO: '#19c8f0,#f3d21f', MONOCHROME: '#f2f2f2,#15161a', TEMPERATUR: '#2152d9,#d5202a',
    SPRUNK: '#2fb24c,#f2f2f2', VICE: '#ff3fb4,#19c8f0', HSW: '#f3d21f,#2152d9', FUBUKI: '#f2f2f2,#19c8f0', MONIKA: '#f065a8,#2fb24c',
    KAMENRIDER: '#2fb24c,#d5202a', NITE: '#16286e,#f3d21f', CHROMABERA: '#d425b5,#19c8f0,#f3d21f',
};
const RAINBOW = '#e0245e,#f07a1c,#f3d21f,#2fb24c,#19c8f0,#5b2be0,#d425b5';

const FAMILY_ORDER = ['BLACK', 'SILVER', 'WHITE', 'RED', 'PINK', 'ORANGE', 'YELLOW', 'GREEN', 'BLUE', 'PURPLE', 'BROWN', 'METALS', 'CHAMELEON'];
const FAMILY_WORDS = [
    [/\bblack\b/i, 'BLACK'], [/\bwhite\b|cream/i, 'WHITE'], [/silver|steel|gr[ae]y|graphite|iron|alumin/i, 'SILVER'],
    [/\bred\b/i, 'RED'], [/pink/i, 'PINK'], [/orange/i, 'ORANGE'], [/yellow|gold|bronze/i, 'YELLOW'], [/green/i, 'GREEN'],
    [/blue/i, 'BLUE'], [/purple/i, 'PURPLE'], [/brown|earth|\btan\b|darb/i, 'BROWN'],
];
const FINISH_LABELS = {
    metallic: 'Metallic', matte: 'Solid Matte', metal: 'Brushed Metal', chrome: 'Chrome', chameleon: 'Chameleon', pearl: 'Pearlescent',
};

function hexToRgb(hex) {
    const n = parseInt(hex.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function shade(hex, amount) { // amount -1..1, towards black or white
    const target = amount < 0 ? 0 : 255;
    const t = Math.abs(amount);
    const [r, g, b] = hexToRgb(hex).map((c) => Math.round(c + (target - c) * t));
    return `rgb(${r},${g},${b})`;
}

function familyOf(option, hex) {
    if (option.finish === 'chameleon') return 'CHAMELEON';
    if (option.finish === 'metal' || option.finish === 'chrome') return 'METALS';
    for (const [pattern, family] of FAMILY_WORDS) {
        if (pattern.test(option.label)) return family;
    }
    const [r, g, b] = hexToRgb(hex).map((c) => c / 255);
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    const light = (max + min) / 2;
    const sat = max === min ? 0 : (max - min) / (1 - Math.abs(2 * light - 1));
    if (sat < 0.16 || light < 0.08) return light < 0.17 ? 'BLACK' : light > 0.78 ? 'WHITE' : 'SILVER';
    let hue = max === r ? ((g - b) / (max - min)) % 6 : max === g ? (b - r) / (max - min) + 2 : (r - g) / (max - min) + 4;
    hue = (hue * 60 + 360) % 360;
    if (hue < 15 || hue >= 345) return 'RED';
    if (hue < 45) return light < 0.38 ? 'BROWN' : 'ORANGE';
    if (hue < 70) return light < 0.4 ? 'BROWN' : 'YELLOW';
    if (hue < 165) return 'GREEN';
    if (hue < 255) return 'BLUE';
    if (hue < 290) return 'PURPLE';
    return 'PINK';
}

function chameleonGradient(label) {
    const stops = [];
    for (const word of label.toUpperCase().split(/\s+/)) {
        if (CHAMELEON_WORDS[word]) stops.push(CHAMELEON_WORDS[word]);
    }
    return `linear-gradient(135deg, ${(stops.length ? stops.join(',') : RAINBOW)})`;
}

// What a swatch of this option looks like: { hex, background, family, finish }
function swatchOf(option) {
    if (option.hex) {
        return { hex: option.hex, background: option.hex, family: option.group || '', finish: '' };
    }
    if (typeof option.value !== 'number') {
        return { hex: null, background: 'none', family: option.group || '', finish: '' };
    }
    const hex = GTA_COLORS[option.value] || '#888888';
    let background = hex;
    if (option.finish === 'chameleon') {
        background = chameleonGradient(option.label);
    } else if (option.finish === 'chrome') {
        background = 'linear-gradient(160deg, #f5f7fa, #9aa3ad 40%, #e9edf1 55%, #6d7680)';
    } else if (option.finish === 'metal') {
        background = `repeating-linear-gradient(90deg, rgba(255,255,255,.09) 0 1px, rgba(0,0,0,0) 1px 3px), ${hex}`;
    } else if (option.finish !== 'matte') {
        background = `linear-gradient(135deg, ${shade(hex, 0.22)} 0%, ${hex} 45%, ${shade(hex, -0.18)} 100%)`;
    }
    return { hex, background, family: option.group || familyOf(option, hex), finish: FINISH_LABELS[option.finish] || '' };
}
