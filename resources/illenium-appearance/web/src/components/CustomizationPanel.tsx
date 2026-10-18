import React, { useState } from 'react';
import Nui from '../Nui';
import { ClothImage } from './ClothImage';

export const GTA_HAIR_COLORS: string[] = [
  "#1c1e1d", "#36302e", "#3c2e28", "#462d22", "#562d1d", "#6e331d", "#7e371e", "#914122",
  "#974c26", "#8b4d2b", "#985832", "#9b6038", "#a66838", "#a66f3b", "#b27a3e", "#b98845",
  "#b48a4c", "#ad844e", "#9a7446", "#6c5035", "#6c5339", "#8c6c44", "#9b7849", "#ab8852",
  "#c8a562", "#d6b56d", "#d1af69", "#d7b46d", "#b58d53", "#8d643b", "#583f28", "#8e3b23",
  "#a03623", "#a82f23", "#9d1f23", "#7d1e23", "#82262d", "#9a3140", "#a63351", "#8b2649",
  "#731e40", "#842557", "#98286a", "#8c2a78", "#5e1e63", "#742278", "#6a1d74", "#3e1957",
  "#28174e", "#251c59", "#1b2064", "#1c326e", "#1d4474", "#1b516b", "#1a5b60", "#1d6d5c",
  "#227b56", "#267b40", "#5b8a36", "#7c932e", "#8c9b32", "#a5a837", "#b3aa37", "#c2a637"
];

const OVERLAY_CATEGORY_MAP: Record<string, string> = {
  'FACIAL HAIR': 'beard',
  'beard': 'beard',
  'EYEBROWS': 'eyebrows',
  'eyebrows': 'eyebrows',
  'MAKEUP': 'makeUp',
  'makeUp': 'makeUp',
  'BLUSH': 'blush',
  'blush': 'blush',
  'LIPSTICK': 'lipstick',
  'lipstick': 'lipstick',
  'CHEST HAIR': 'chestHair',
  'chestHair': 'chestHair',
};

export default function CustomizationPanel({
  activeCategory,
  activeItem,
  appearanceData,
  setAppearanceData,
  setTotalCost,
  gender,
  onTextureSelect,
}: {
  activeCategory: string;
  activeItem?: any;
  appearanceData?: any;
  setAppearanceData?: React.Dispatch<React.SetStateAction<any>>;
  setTotalCost?: (cost: (prev: number) => number) => void;
  gender?: 'male' | 'female';
  totalCost?: number;
  onTextureSelect?: (textureId: number) => void;
}) {
  const [colorTarget, setColorTarget] = useState<'primary' | 'secondary'>('primary');
  const [mixType, setMixType] = useState<'mixA' | 'mixB'>('mixB');

  const isHairCat = activeCategory === 'HAIR' || activeCategory === 'STYLES' || activeCategory === 'HAIRSTYLE';
  const overlayKey = OVERLAY_CATEGORY_MAP[activeCategory];
  const isColorCat = isHairCat || !!overlayKey;

  // 1. Color Customization Mode (Hair, Beard, Eyebrows, Makeup, Blush, Lipstick, Chest Hair)
  if (isColorCat) {
    let primaryColor = 0;
    let secondaryColor = 0;
    let styleVal = 0;
    let opacityVal = 1.0;

    if (isHairCat) {
      styleVal = appearanceData?.hair?.style !== undefined ? appearanceData.hair.style : (activeItem?.drawable ?? 0);
      primaryColor = appearanceData?.hair?.color ?? 0;
      secondaryColor = appearanceData?.hair?.highlight ?? 0;
    } else if (overlayKey) {
      const ov = appearanceData?.headOverlays?.[overlayKey] || {};
      styleVal = ov.style ?? 0;
      opacityVal = ov.opacity ?? 1.0;
      primaryColor = ov.color ?? 0;
      secondaryColor = ov.secondColor ?? 0;
    }

    const handleSelectColor = (cIdx: number) => {
      if (setTotalCost) setTotalCost(prev => prev + 10);

      if (isHairCat) {
        const newPrimary = colorTarget === 'primary' ? cIdx : primaryColor;
        const newSecondary = colorTarget === 'secondary' ? cIdx : secondaryColor;
        
        if (setAppearanceData) {
          setAppearanceData((prev: any) => ({
            ...prev,
            hair: {
              ...(prev?.hair || {}),
              style: styleVal,
              color: newPrimary,
              highlight: newSecondary
            }
          }));
        }
        Nui.post('appearance_change_hair', {
          style: styleVal,
          color: newPrimary,
          highlight: newSecondary
        });
      } else if (overlayKey) {
        const newPrimary = colorTarget === 'primary' ? cIdx : primaryColor;
        const newSecondary = colorTarget === 'secondary' ? cIdx : secondaryColor;
        const updatedOverlay = {
          style: styleVal,
          opacity: opacityVal,
          color: newPrimary,
          secondColor: newSecondary
        };

        if (setAppearanceData) {
          setAppearanceData((prev: any) => ({
            ...prev,
            headOverlays: {
              ...(prev?.headOverlays || {}),
              [overlayKey]: updatedOverlay
            }
          }));
        }
        Nui.post('appearance_change_head_overlay', {
          key: overlayKey,
          style: styleVal,
          opacity: opacityVal,
          color: newPrimary,
          secondColor: newSecondary
        });
      }
    };

    const handleOpacityChange = (newOpacity: number) => {
      const clamped = Math.min(Math.max(newOpacity, 0.0), 1.0);
      if (overlayKey) {
        const updatedOverlay = {
          style: styleVal,
          opacity: clamped,
          color: primaryColor,
          secondColor: secondaryColor
        };
        if (setAppearanceData) {
          setAppearanceData((prev: any) => ({
            ...prev,
            headOverlays: {
              ...(prev?.headOverlays || {}),
              [overlayKey]: updatedOverlay
            }
          }));
        }
        Nui.post('appearance_change_head_overlay', {
          key: overlayKey,
          style: styleVal,
          opacity: clamped,
          color: primaryColor,
          secondColor: secondaryColor
        });
      }
    };

    const currentSelectedColorIndex = colorTarget === 'primary' ? primaryColor : secondaryColor;
    const primaryHex = GTA_HAIR_COLORS[primaryColor] || '#1c1e1d';
    const secondaryHex = GTA_HAIR_COLORS[secondaryColor] || '#1c1e1d';

    return (
      <div className="w-[380px] flex flex-col gap-3 pointer-events-auto select-none">
        {/* Title */}
        <h1 className="text-[52px] font-bebas italic text-white tracking-wider mb-1 uppercase text-center opacity-95 leading-none">
          CUSTOMIZATION
        </h1>

        {/* SECTION 1: COLORS */}
        <div className="flex flex-col gap-1 shadow-md">
          <div className="bg-white text-black font-oswald font-bold px-3 py-1 text-sm uppercase tracking-wider">
            COLORS
          </div>
          <div className="bg-[#16181f]/95 p-2.5 border border-white/5 grid grid-cols-2 gap-2">
            {/* Primary Target Button */}
            <button
              type="button"
              onClick={() => setColorTarget('primary')}
              className={`
                flex flex-col items-center p-1.5 transition-all cursor-pointer bg-[#0e1015] border
                ${colorTarget === 'primary' ? 'border-cyan-400 ring-2 ring-cyan-400/50' : 'border-white/10 hover:border-white/30'}
              `}
            >
              <div 
                className="w-full h-12 rounded-none border border-black/40 shadow-inner mb-1.5"
                style={{ backgroundColor: primaryHex }}
              />
              <span className="font-oswald font-bold text-xs text-white uppercase tracking-wider">
                PRIMARY
              </span>
            </button>

            {/* Secondary Target Button */}
            <button
              type="button"
              onClick={() => setColorTarget('secondary')}
              className={`
                flex flex-col items-center p-1.5 transition-all cursor-pointer bg-[#0e1015] border
                ${colorTarget === 'secondary' ? 'border-cyan-400 ring-2 ring-cyan-400/50' : 'border-white/10 hover:border-white/30'}
              `}
            >
              <div 
                className="w-full h-12 rounded-none border border-black/40 shadow-inner mb-1.5"
                style={{
                  background: mixType === 'mixB' 
                    ? `linear-gradient(135deg, ${primaryHex} 0%, ${secondaryHex} 100%)`
                    : secondaryHex
                }}
              />
              <span className="font-oswald font-bold text-xs text-white uppercase tracking-wider">
                SECONDARY
              </span>
            </button>
          </div>
        </div>

        {/* SECTION 2: PICK COLOR (64 Palette Grid) */}
        <div className="flex flex-col gap-1 shadow-md">
          <div className="bg-white text-black font-oswald font-bold px-3 py-1 text-sm uppercase tracking-wider flex justify-between items-center">
            <span>PICK COLOR</span>
            <span className="text-xs text-zinc-600 font-normal">COLOR #{currentSelectedColorIndex}</span>
          </div>
          <div className="bg-[#16181f]/95 p-2 border border-white/5">
            <div className="grid grid-cols-8 gap-1.5 max-h-[220px] overflow-y-auto styled-scrollbar pr-1">
              {GTA_HAIR_COLORS.map((hex, idx) => {
                const isActive = currentSelectedColorIndex === idx;
                return (
                  <button
                    key={idx}
                    type="button"
                    onClick={() => handleSelectColor(idx)}
                    title={`Color #${idx}`}
                    className={`
                      aspect-square w-full rounded-none transition-all cursor-pointer relative flex items-center justify-center
                      ${isActive ? 'ring-2 ring-cyan-400 border-2 border-white scale-105 z-10 shadow-lg' : 'hover:scale-110 hover:z-20 border border-black/50'}
                    `}
                    style={{ backgroundColor: hex }}
                  >
                    {isActive && (
                      <div className="w-1.5 h-1.5 bg-white rounded-full shadow-sm" />
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* SECTION 3: COLOR MIXING TYPE & FADE */}
        <div className="flex flex-col gap-1 shadow-md">
          <div className="bg-white text-black font-oswald font-bold px-3 py-1 text-sm uppercase tracking-wider">
            COLOR MIXING TYPE
          </div>
          <div className="bg-[#16181f]/95 p-2.5 border border-white/5 flex flex-col gap-2.5">
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setMixType('mixA')}
                className={`
                  flex flex-col items-center p-1.5 transition-all cursor-pointer bg-[#0e1015] border
                  ${mixType === 'mixA' ? 'border-cyan-400 ring-2 ring-cyan-400/50' : 'border-white/10 hover:border-white/30'}
                `}
              >
                <div 
                  className="w-full h-10 border border-black/40 shadow-inner mb-1"
                  style={{ backgroundColor: primaryHex }}
                />
                <span className="font-oswald font-bold text-[11px] text-white uppercase tracking-wider">
                  COLOR MIX A
                </span>
              </button>

              <button
                type="button"
                onClick={() => setMixType('mixB')}
                className={`
                  flex flex-col items-center p-1.5 transition-all cursor-pointer bg-[#0e1015] border
                  ${mixType === 'mixB' ? 'border-cyan-400 ring-2 ring-cyan-400/50' : 'border-white/10 hover:border-white/30'}
                `}
              >
                <div 
                  className="w-full h-10 border border-black/40 shadow-inner mb-1"
                  style={{ background: `linear-gradient(135deg, ${primaryHex} 0%, ${secondaryHex} 100%)` }}
                />
                <span className="font-oswald font-bold text-[11px] text-white uppercase tracking-wider">
                  COLOR MIX B
                </span>
              </button>
            </div>

            {/* Opacity / Fade Slider for Head Overlays */}
            {overlayKey && (
              <div className="flex flex-col gap-1 pt-1 border-t border-white/10">
                <div className="flex justify-between items-center text-xs font-oswald font-bold text-white uppercase tracking-wider">
                  <span>FADE & OPACITY</span>
                  <span className="bg-black text-cyan-400 px-1.5 py-0.5">{Math.round(opacityVal * 100)}%</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="font-bebas italic text-xs text-white/70">MIN</span>
                  <input
                    type="range"
                    min="0"
                    max="1"
                    step="0.05"
                    value={opacityVal}
                    onChange={(e) => handleOpacityChange(parseFloat(e.target.value))}
                    className="flex-1 h-1.5 rounded-none appearance-none cursor-pointer"
                    style={{
                      background: `linear-gradient(to right, #00c8ff ${opacityVal * 100}%, #3f3f46 ${opacityVal * 100}%)`
                    }}
                  />
                  <span className="font-bebas italic text-xs text-white/70">MAX</span>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    );
  }

  // 2. Texture Grid Mode (for Component & Prop Items)
  if (!activeCategory || !activeItem) return null;

  const type = activeItem.component_id !== undefined ? 'component' : 'prop';
  const itemId = type === 'component' ? activeItem.component_id : activeItem.prop_id;

  const handleUpdateTexture = (textureId: number) => {
    if (setTotalCost) setTotalCost(prev => prev + 10);
    if (type === 'component') {
      Nui.post('appearance_change_component', {
        component_id: itemId,
        drawable: activeItem.drawable,
        texture: textureId,
      });
    } else {
      Nui.post('appearance_change_prop', {
        prop_id: itemId,
        drawable: activeItem.drawable,
        texture: textureId,
      });
    }
    if (onTextureSelect) {
      onTextureSelect(textureId);
    }
  };

  const maxTextures = 9; // 3x3 texture grid
  const currentTexture = activeItem.texture || 0;


  return (
    <div className="w-[380px] flex flex-col pointer-events-auto select-none">
      {/* Title */}
      <h1 className="text-[52px] font-bebas italic text-white tracking-wider mb-2 uppercase text-center opacity-95 leading-none">
        CUSTOMIZATION
      </h1>

      {/* STYLES tab */}
      <div className="flex gap-[2px]">
        <div className="flex-1 py-1.5 text-[14px] font-oswald font-bold tracking-wider uppercase text-center bg-white text-black">
          STYLES
        </div>
      </div>

      {/* White accent line */}
      <div className="w-full h-[3px] bg-white" />

      {/* Texture grid */}
      <div className="flex flex-col bg-transparent p-0">
        <div className="grid grid-cols-3 gap-1.5 pr-1">
          {Array.from({ length: maxTextures }).map((_, tex) => {
            const isActive = currentTexture === tex;
            return (
              <button
                key={tex}
                type="button"
                onClick={() => handleUpdateTexture(tex)}
                className={`
                  relative flex flex-col aspect-[4/5] bg-[#181a20] transition-all cursor-pointer overflow-hidden
                  ${isActive ? 'ring-2 ring-white border border-white z-10' : 'border border-white/5 hover:border-white/40'}
                `}
              >
                <div className="flex-1 w-full flex items-center justify-center overflow-hidden p-1">
                  <ClothImage
                    type={type === 'component' ? 'component' : 'prop'}
                    id={itemId}
                    drawable={activeItem.drawable}
                    texture={tex}
                    gender={gender}
                    className="w-full h-full object-contain"
                    placeholderClassName="w-10 h-10 opacity-20 grayscale"
                  />
                </div>
                <div className="w-full bg-[#0a0b0e] px-1 py-1 flex items-center justify-center">
                  <span className="text-[10px] font-oswald text-white/90 uppercase font-bold tracking-wide">
                    TEXTURE {tex}
                  </span>
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
