import React, { useState } from 'react';
import Nui from '../Nui';
import { Filter, Trash2, Check, Search, X } from 'lucide-react';
import { getCategoryLucideIcon } from './CategoryIcons';
import { getPedImageCandidates, getCachedAssetImage, setCachedAssetImage, getModelThumbDataUri } from '../utils';
import { ClothImage } from './ClothImage';
import { TattooImage } from './TattooImage';

function PedCardImage({ model }: { model: string }) {
  const candidates = React.useMemo(() => getPedImageCandidates(model), [model]);
  const [srcIndex, setSrcIndex] = useState(0);

  const fallbackUri = getModelThumbDataUri(model, "ped");
  const currentSrc = srcIndex < candidates.length ? candidates[srcIndex] : fallbackUri;

  return (
    <img
      src={currentSrc}
      alt={model}
      onError={() => {
        setSrcIndex(prev => prev + 1);
      }}
      onLoad={() => {
        if (currentSrc && !currentSrc.startsWith("data:")) {
          setCachedAssetImage(model, "ped", currentSrc);
        }
      }}
      className="w-full h-full object-contain p-1"
    />
  );
}

const APPAREL_CATEGORIES = [
  { id: 'OUTFITS', label: 'OUTFITS' },
  { id: 'CLOTHING', label: 'CLOTHING' },
  { id: 'UPPER BODY ACCESSORIES', label: 'UPPER BODY ACCESSORIES' },
  { id: 'HAND & WRIST ACCESSORIES', label: 'HAND & WRIST ACCESSORIES' },
  { id: 'HEAD ACCESSORIES', label: 'HEAD ACCESSORIES' },
];

const APPAREL_SUBCATEGORIES: Record<string, { label: string; cam: string }[]> = {
  'CLOTHING': [
    { label: 'TOPS', cam: 'body' },
    { label: 'UNDERSHIRTS', cam: 'body' },
    { label: 'BOTTOMS', cam: 'legs' },
    { label: 'SHOES', cam: 'shoes' },
  ],
  'UPPER BODY ACCESSORIES': [
    { label: 'BODY ARMOR', cam: 'body' },
    { label: 'BAGS & PARACHUTES', cam: 'body' },
    { label: 'DECALS', cam: 'body' },
  ],
  'HAND & WRIST ACCESSORIES': [
    { label: 'GLOVES', cam: 'body' },
    { label: 'WATCHES', cam: 'body' },
    { label: 'BRACELETS', cam: 'body' },
  ],
  'HEAD ACCESSORIES': [
    { label: 'MASKS', cam: 'head' },
    { label: 'HATS', cam: 'head' },
    { label: 'GLASSES', cam: 'head' },
    { label: 'EARS', cam: 'head' },
  ],
  'OUTFITS': [
    { label: 'SAVED OUTFITS', cam: 'body' },
  ]
};

const TATTOO_ZONES = [
  { label: 'ZONE_HEAD' },
  { label: 'ZONE_TORSO' },
  { label: 'ZONE_LEFT_ARM' },
  { label: 'ZONE_RIGHT_ARM' },
  { label: 'ZONE_LEFT_LEG' },
  { label: 'ZONE_RIGHT_LEG' },
];

export default function Grid({ 
  navPath,
  setNavPath,
  activeCategory, 
  itemType, 
  itemId, 
  itemsToRender, 
  activeItem,
  setTotalCost,
  gender,
  appearanceData,
  onItemSelect
}: { 
  navPath: string[];
  setNavPath: (path: string[]) => void;
  activeCategory: string;
  itemType: string;
  itemId: number;
  itemsToRender: any[];
  activeItem: any;
  setTotalCost?: (cost: (prev: number) => number) => void;
  gender?: 'male' | 'female';
  appearanceData?: any;
  onItemSelect?: (item: any) => void;
}) {
  const [searchQuery, setSearchQuery] = useState('');

  if (!activeCategory || itemsToRender.length === 0) return null;

  const handleUpdateItem = (drawable: number, texture: number) => {
    if (setTotalCost && itemType !== 'ped_model') setTotalCost(prev => prev + 100);

    if (itemType === 'ped_model') {
      const targetItem = itemsToRender[drawable] || itemsToRender.find(it => it.drawable === drawable);
      const modelName = targetItem?.model || targetItem?.name;
      if (modelName) {
        Nui.post('appearance_change_model', modelName).then((res: any) => {
          if (res?.appearanceData && onItemSelect) {
            onItemSelect(res.appearanceData);
          }
        });
        if (onItemSelect) onItemSelect(targetItem);
      }
      return;
    }

    if (itemType === 'tattoo') {
      const tattooItem = itemsToRender[drawable] || itemsToRender.find(it => it.drawable === drawable);
      if (tattooItem) {
        Nui.post('appearance_apply_tattoo', { tattoo: tattooItem, updatedTattoos: [tattooItem] });
        if (onItemSelect) onItemSelect(tattooItem);
      }
      return;
    }

    if (itemType === 'component') {
      Nui.post('appearance_change_component', { component_id: itemId, drawable, texture });
      if (onItemSelect) onItemSelect({ component_id: itemId, drawable, texture });
    } else if (itemType === 'prop') {
      Nui.post('appearance_change_prop', { prop_id: itemId, drawable, texture });
      if (onItemSelect) onItemSelect({ prop_id: itemId, drawable, texture });
    } else if (itemType === 'eye_color') {
      Nui.post('appearance_change_eye_color', drawable);
      if (onItemSelect) onItemSelect({ drawable, texture: 0 });
    } else if (itemType === 'hair') {
      const color = appearanceData?.hair?.color || 0;
      const highlight = appearanceData?.hair?.highlight || 0;
      Nui.post('appearance_change_hair', { style: drawable, color, highlight });
      if (onItemSelect) onItemSelect({ drawable, texture: 0 });
    }
  };

  const handleRemoveItem = () => {
    if (itemType === 'component') {
      Nui.post('appearance_change_component', { component_id: itemId, drawable: 0, texture: 0 });
      if (onItemSelect) onItemSelect({ component_id: itemId, drawable: 0, texture: 0 });
    } else if (itemType === 'prop') {
      Nui.post('appearance_change_prop', { prop_id: itemId, drawable: -1, texture: 0 });
      if (onItemSelect) onItemSelect({ prop_id: itemId, drawable: -1, texture: 0 });
    } else if (itemType === 'tattoo') {
      if (activeItem) {
        Nui.post('appearance_delete_tattoo', activeItem);
        if (onItemSelect) onItemSelect(null);
      }
    }
  };

  const handleNavigateBack = () => {
    if (navPath.length > 1) {
      setNavPath(navPath.slice(0, -1));
    }
  };

  const mainTab = navPath[0];
  const currentFolder = navPath.length >= 2 ? navPath[1] : '';
  const currentSubList = APPAREL_SUBCATEGORIES[currentFolder] || [];

  // Filter items based on search query
  const filteredItems = itemsToRender.filter(item => {
    if (!searchQuery.trim()) return true;
    const q = searchQuery.toLowerCase().trim();
    if (itemType === 'ped_model') {
      const modelName = (item.model || item.name || '').toLowerCase();
      const cleanModelName = modelName.replace(/_/g, ' ');
      const cleanQ = q.replace(/_/g, ' ');
      return modelName.includes(q) || cleanModelName.includes(cleanQ);
    }
    if (itemType === 'tattoo') {
      const label = (item.label || item.name || '').toLowerCase();
      const coll = (item.collection || '').toLowerCase();
      return label.includes(q) || coll.includes(q);
    }
    const name = `${activeCategory} ${item.drawable}`.toLowerCase();
    return name.includes(q) || String(item.drawable).includes(q);
  });

  return (
    <div className="w-[660px] flex flex-col pointer-events-auto ml-12 mt-8 select-none relative z-10">
      {/* Clean Header displaying full navigation path steps with size hierarchy */}
      <div className="flex items-center gap-3.5 mb-4 h-12 whitespace-nowrap min-w-max">
        <button 
          onClick={handleNavigateBack}
          className="w-12 h-12 bg-white text-black font-bold text-2xl flex items-center justify-center hover:bg-zinc-200 transition-colors shadow-lg cursor-pointer flex-shrink-0"
          title="Go Back"
        >
          {'<'}
        </button>
        <div className="font-bebas italic tracking-wider uppercase leading-none pt-1 whitespace-nowrap flex items-baseline gap-3">
          {navPath.map((step, idx) => {
            const fontClasses = [
              'text-[40px] text-white font-bold',
              'text-[30px] text-white/80 font-semibold',
              'text-[22px] text-white/60 font-medium'
            ];
            const sizeClass = fontClasses[Math.min(idx, fontClasses.length - 1)];
            return (
              <button
                key={idx}
                type="button"
                onClick={() => {
                  if (idx < navPath.length - 1) {
                    setNavPath(navPath.slice(0, idx + 1));
                  }
                }}
                className={`transition-colors uppercase ${sizeClass} ${
                  idx < navPath.length - 1 ? 'hover:text-white cursor-pointer' : 'cursor-default'
                }`}
              >
                {step}
              </button>
            );
          })}
        </div>
      </div>

      <div className="flex gap-[3px]">
        {/* Left Side Icon Columns for APPAREL */}
        {mainTab === 'APPAREL' && (
          <div className="flex gap-[3px]">
            {/* Column 1: Parent Folders */}
            <div className="w-[52px] flex flex-col gap-[3px]">
              {APPAREL_CATEGORIES.map(cat => {
                const isFolderActive = currentFolder === cat.label;
                return (
                  <button 
                    key={cat.id}
                    title={cat.label}
                    onClick={() => {
                      const firstSub = (APPAREL_SUBCATEGORIES[cat.label] && APPAREL_SUBCATEGORIES[cat.label][0]?.label) || cat.label;
                      setNavPath(['APPAREL', cat.label, firstSub]);
                    }}
                    className={`
                      w-full h-[52px] flex items-center justify-center transition-all cursor-pointer
                      ${isFolderActive 
                        ? 'bg-white/20 text-white border-l-2 border-white' 
                        : 'bg-[#181a20]/90 text-white/35 hover:text-white/80 hover:bg-zinc-800'}
                    `}
                  >
                    {getCategoryLucideIcon(cat.label, "w-6 h-6")}
                  </button>
                );
              })}
            </div>

            {/* Column 2: Subcategories (Active is crisp white square [ 👕 ]) */}
            {currentSubList.length > 0 && (
              <div className="w-[52px] flex flex-col gap-[3px]">
                {currentSubList.map(sub => {
                  const isSubActive = activeCategory === sub.label;
                  return (
                    <button 
                      key={sub.label}
                      title={sub.label}
                      onClick={() => {
                        setNavPath(['APPAREL', currentFolder, sub.label]);
                      }}
                      className={`
                        w-full h-[52px] flex items-center justify-center transition-all cursor-pointer shadow-md
                        ${isSubActive 
                          ? 'bg-white text-black ring-1 ring-white' 
                          : 'bg-[#181a20]/90 text-white/40 hover:text-white hover:bg-zinc-800'}
                      `}
                    >
                      {getCategoryLucideIcon(sub.label, `w-6 h-6 ${isSubActive ? 'text-black' : 'text-white/40'}`)}
                    </button>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* Left Side Icon Column for TATTOOS */}
        {mainTab === 'TATTOOS' && (
          <div className="w-[52px] flex flex-col gap-[3px]">
            {TATTOO_ZONES.map(sub => {
              const isSubActive = activeCategory === sub.label || (navPath.length === 1 && sub.label === 'ZONE_HEAD');
              return (
                <button 
                  key={sub.label}
                  title={sub.label.replace('ZONE_', '').replace('_', ' ')}
                  onClick={() => {
                    setNavPath(['TATTOOS', sub.label]);
                  }}
                  className={`
                    w-full h-[52px] flex items-center justify-center transition-all cursor-pointer shadow-md
                    ${isSubActive 
                      ? 'bg-white text-black ring-1 ring-white' 
                      : 'bg-[#181a20]/90 text-white/40 hover:text-white hover:bg-zinc-800'}
                  `}
                >
                  {getCategoryLucideIcon(sub.label, `w-6 h-6 ${isSubActive ? 'text-black' : 'text-white/40'}`)}
                </button>
              );
            })}
          </div>
        )}

        {/* Main Grid Area */}
        <div className="flex-1 flex flex-col bg-transparent p-0">
          {/* Search and Action Bar */}
          <div className="flex gap-[3px] mb-3">
            <div className="flex-1 bg-[#181a20] flex items-center px-3 py-1.5 gap-2 border border-white/5 focus-within:border-white">
              <svg className="w-4 h-4 text-zinc-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path>
              </svg>
              <input 
                type="text" 
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search..." 
                className="bg-transparent border-none outline-none text-sm font-oswald text-white w-full placeholder-zinc-500" 
              />
              {searchQuery && (
                <button onClick={() => setSearchQuery('')} className="text-xs text-zinc-400 hover:text-white">✕</button>
              )}
            </div>
            
            {/* Filter Button */}
            <button 
              title="Filter"
              className="w-10 h-10 bg-[#181a20] border border-white/5 flex items-center justify-center text-zinc-400 hover:text-white hover:bg-zinc-800 transition-colors cursor-pointer"
            >
              <Filter className="w-5 h-5" />
            </button>

            {/* Undress / Clear Button */}
            <button 
              title="Remove Item"
              onClick={handleRemoveItem}
              className="w-10 h-10 bg-[#181a20] border border-white/5 flex items-center justify-center text-zinc-400 hover:text-white hover:bg-zinc-800 transition-colors cursor-pointer"
            >
              <Trash2 className="w-5 h-5" />
            </button>
          </div>

          {/* Cards Grid — 4 Columns (rows as tall as their cards: else a long list's rows are squeezed into the
              height and the cards drawn over each other) */}
          <div className="grid grid-cols-4 auto-rows-max gap-1.5 overflow-y-auto max-h-[72vh] pr-1 styled-scrollbar">
            {filteredItems.map((item, idx) => {
              const isPedModel = itemType === 'ped_model';
              const isTattoo = itemType === 'tattoo';
              const isActive = isPedModel 
                ? (appearanceData?.model === item.model || activeItem?.model === item.model)
                : isTattoo
                ? (appearanceData?.tattoos?.some((t: any) => t.name === item.name || t.label === item.label) || activeItem?.name === item.name)
                : (activeItem?.drawable === item.drawable);

              let itemName = isPedModel
                ? (item.model || item.name || '')
                : isTattoo
                ? (item.label || item.name || '')
                : `${activeCategory} ${item.drawable}`;

              const variantCount = (!isPedModel && !isTattoo) ? (item.drawable % 3 === 1 ? 1 : item.drawable % 5 === 0 ? 2 : 0) : 0;

              return (
                <button
                  key={idx}
                  onClick={() => handleUpdateItem(item.drawable, item.texture)}
                  className={`
                    relative flex flex-col aspect-[4/5] bg-[#181a20] group transition-all cursor-pointer overflow-hidden
                    ${isActive ? 'ring-2 ring-white border border-white z-10' : 'border border-white/5 hover:border-white/40'}
                  `}
                >
                  {/* Variant Badge */}
                  {variantCount > 0 && (
                    <div className="absolute top-1 right-1 bg-white text-black font-oswald font-bold text-[11px] px-1.5 py-0.5 leading-none shadow z-20">
                      {variantCount}
                    </div>
                  )}

                  {/* Image / Avatar area */}
                  <div className="flex-1 w-full flex flex-col items-center justify-center overflow-hidden p-2 relative">
                    {isPedModel ? (
                      <PedCardImage model={item.model || item.name} />
                    ) : isTattoo ? (
                      <TattooImage tattoo={item} gender={gender} />
                    ) : itemType === 'eye_color' ? (
                      <img src="./files/faces/SKEL_ROOT.000.webp" className="w-full h-full object-contain" />
                    ) : (
                      <ClothImage
                        type={itemType === 'hair' || itemType === 'component' ? 'component' : 'prop'}
                        id={itemType === 'hair' ? 2 : itemId}
                        drawable={item.drawable}
                        gender={gender}
                        className="w-full h-full object-contain"
                        placeholderClassName="w-12 h-12 opacity-25 grayscale"
                      />
                    )}
                  </div>

                  {/* Bottom Bar: Name on left, Price or Checkmark on right */}
                  <div className="w-full bg-[#0d0e12] px-2 py-1.5 flex items-center justify-between min-h-[30px]">
                    <span className="text-[11px] font-oswald text-white/90 truncate uppercase tracking-wider font-medium text-left pr-1">
                      {itemName}
                    </span>

                    {isActive ? (
                      <div className="text-white flex-shrink-0">
                        <Check className="w-4 h-4" />
                      </div>
                    ) : (
                      <div className="bg-white text-black px-1.5 py-0.5 flex items-center gap-0.5 leading-none flex-shrink-0">
                        <span className="text-[9px] font-bold">$</span>
                        <span className="font-oswald text-[11px] font-bold">100</span>
                      </div>
                    )}
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
