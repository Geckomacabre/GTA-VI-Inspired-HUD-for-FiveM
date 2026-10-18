import React from 'react';
import Nui from '../Nui';
import { getCategoryLucideIcon } from './CategoryIcons';

const FEATURE_NAMES: Record<string, string> = {
  // Head Blend
  'shapeFirst': 'Mother Face Shape',
  'shapeSecond': 'Father Face Shape',
  'skinFirst': 'Mother Skin Tone',
  'skinSecond': 'Father Skin Tone',
  'shapeMix': 'Face Shape Mix',
  'skinMix': 'Skin Tone Mix',
  // Nose
  'noseWidth': 'Nose Width',
  'nosePeakHigh': 'Nose Peak Height',
  'nosePeakSize': 'Nose Peak Size',
  'noseBoneHigh': 'Nose Bone Height',
  'nosePeakLowering': 'Nose Peak Lowering',
  'noseBoneTwist': 'Nose Bone Twist',
  // Eyes & Cheeks
  'eyeBrownHigh': 'Brow Height',
  'eyeBrownForward': 'Brow Depth',
  'cheeksBoneHigh': 'Cheekbone Height',
  'cheeksBoneWidth': 'Cheekbone Width',
  'cheeksWidth': 'Cheek Width',
  'eyesOpening': 'Eye Opening',
  // Lips & Jaw
  'lipsThickness': 'Lip Thickness',
  'jawBoneWidth': 'Jaw Width',
  'jawBoneBackSize': 'Jaw Depth',
  // Chin & Neck
  'chinBoneLowering': 'Chin Height',
  'chinBoneLenght': 'Chin Length',
  'chinBoneSize': 'Chin Width',
  'chinHole': 'Chin Hole',
  'neckThickness': 'Neck Thickness',
  // Overlays
  'blemishes': 'Blemishes',
  'beard': 'Facial Hair',
  'eyebrows': 'Eyebrows',
  'ageing': 'Ageing',
  'makeUp': 'Makeup',
  'blush': 'Blush',
  'complexion': 'Complexion',
  'sunDamage': 'Sun Damage',
  'lipstick': 'Lipstick',
  'moleAndFreckles': 'Moles & Freckles',
  'chestHair': 'Chest Hair',
  'bodyBlemishes': 'Body Blemishes',
};

const FEATURE_LABELS: Record<string, { title: string; minLabel: string; maxLabel: string }> = {
  // Nose
  'noseWidth': { title: 'WIDTH', minLabel: 'THIN', maxLabel: 'WIDE' },
  'nosePeakHigh': { title: 'HEIGHT', minLabel: 'DOWN', maxLabel: 'UP' },
  'nosePeakSize': { title: 'LENGTH', minLabel: 'SHORT', maxLabel: 'LONG' },
  'noseBoneHigh': { title: 'BONE HEIGHT', minLabel: 'LOW', maxLabel: 'HIGH' },
  'nosePeakLowering': { title: 'PEAK LOWERING', minLabel: 'DOWN', maxLabel: 'UP' },
  'noseBoneTwist': { title: 'TWIST', minLabel: 'LEFT', maxLabel: 'RIGHT' },
  // Eyes & Cheeks
  'eyeBrownHigh': { title: 'BROW HEIGHT', minLabel: 'LOW', maxLabel: 'HIGH' },
  'eyeBrownForward': { title: 'BROW DEPTH', minLabel: 'OUT', maxLabel: 'IN' },
  'cheeksBoneHigh': { title: 'CHEEKBONE HEIGHT', minLabel: 'LOW', maxLabel: 'HIGH' },
  'cheeksBoneWidth': { title: 'CHEEKBONE WIDTH', minLabel: 'THIN', maxLabel: 'WIDE' },
  'cheeksWidth': { title: 'CHEEK WIDTH', minLabel: 'THIN', maxLabel: 'WIDE' },
  'eyesOpening': { title: 'EYE OPENING', minLabel: 'CLOSED', maxLabel: 'OPEN' },
  // Lips & Jaw
  'lipsThickness': { title: 'LIP THICKNESS', minLabel: 'THIN', maxLabel: 'THICK' },
  'jawBoneWidth': { title: 'JAW WIDTH', minLabel: 'THIN', maxLabel: 'WIDE' },
  'jawBoneBackSize': { title: 'JAW DEPTH', minLabel: 'SHORT', maxLabel: 'LONG' },
  // Chin & Neck
  'chinBoneLowering': { title: 'CHIN HEIGHT', minLabel: 'DOWN', maxLabel: 'UP' },
  'chinBoneLenght': { title: 'CHIN LENGTH', minLabel: 'SHORT', maxLabel: 'LONG' },
  'chinBoneSize': { title: 'CHIN WIDTH', minLabel: 'SMALL', maxLabel: 'LARGE' },
  'chinHole': { title: 'CHIN HOLE', minLabel: 'NONE', maxLabel: 'DEEP' },
  'neckThickness': { title: 'NECK THICKNESS', minLabel: 'THIN', maxLabel: 'THICK' },
  // Head Blend
  'shapeFirst': { title: 'MOTHER FACE SHAPE', minLabel: 'BENJAMIN', maxLabel: 'HANNAH' },
  'shapeSecond': { title: 'FATHER FACE SHAPE', minLabel: 'BENJAMIN', maxLabel: 'HANNAH' },
  'skinFirst': { title: 'MOTHER SKIN TONE', minLabel: 'LIGHT', maxLabel: 'DARK' },
  'skinSecond': { title: 'FATHER SKIN TONE', minLabel: 'LIGHT', maxLabel: 'DARK' },
  'shapeMix': { title: 'FACE SHAPE MIX', minLabel: 'MOTHER', maxLabel: 'FATHER' },
  'skinMix': { title: 'SKIN TONE MIX', minLabel: 'MOTHER', maxLabel: 'FATHER' },
  // Overlays
  'blemishes': { title: 'BLEMISHES', minLabel: 'NONE', maxLabel: 'MAX' },
  'beard': { title: 'FACIAL HAIR', minLabel: 'CLEAN', maxLabel: 'FULL' },
  'eyebrows': { title: 'EYEBROWS', minLabel: 'CLEAN', maxLabel: 'THICK' },
  'ageing': { title: 'AGEING', minLabel: 'YOUNG', maxLabel: 'OLD' },
  'makeUp': { title: 'MAKEUP', minLabel: 'NONE', maxLabel: 'HEAVY' },
  'blush': { title: 'BLUSH', minLabel: 'NONE', maxLabel: 'FULL' },
  'complexion': { title: 'COMPLEXION', minLabel: 'CLEAR', maxLabel: 'HEAVY' },
  'sunDamage': { title: 'SUN DAMAGE', minLabel: 'NONE', maxLabel: 'HEAVY' },
  'lipstick': { title: 'LIPSTICK', minLabel: 'NONE', maxLabel: 'FULL' },
  'moleAndFreckles': { title: 'MOLES & FRECKLES', minLabel: 'NONE', maxLabel: 'HEAVY' },
  'chestHair': { title: 'CHEST HAIR', minLabel: 'CLEAN', maxLabel: 'FULL' },
  'bodyBlemishes': { title: 'BODY BLEMISHES', minLabel: 'NONE', maxLabel: 'HEAVY' },
};

const SUBCATEGORIES_BY_TAB: Record<string, { label: string }[]> = {
  'FACE ADJUSTMENTS': [
    { label: 'NOSE' },
    { label: 'BROW' },
    { label: 'EYES' },
    { label: 'CHEEKS' },
    { label: 'LIPS & JAW' },
    { label: 'CHIN & NECK' }
  ],
  'FACE & BODY': [
    { label: 'HEAD BLEND' },
    { label: 'EYE COLOR' },
    { label: 'FACE FEATURES' }
  ],
  'OVERLAYS': [
    { label: 'BLEMISHES' },
    { label: 'AGEING' },
    { label: 'COMPLEXION' },
    { label: 'SUN DAMAGE' },
    { label: 'MOLES & FRECKLES' },
    { label: 'BODY BLEMISHES' },
    { label: 'MAKEUP' },
    { label: 'BLUSH' },
    { label: 'LIPSTICK' },
    { label: 'FACIAL HAIR' },
    { label: 'EYEBROWS' },
    { label: 'CHEST HAIR' }
  ],
  'HAIR': [
    { label: 'STYLES' },
    { label: 'FACIAL HAIR' },
    { label: 'EYEBROWS' },
    { label: 'CHEST HAIR' }
  ]
};

export default function Sliders({
  navPath,
  setNavPath,
  activeCategory,
  appearanceData,
  setAppearanceData,
  setTotalCost
}: {
  navPath: string[];
  setNavPath: (path: string[]) => void;
  activeCategory: string;
  appearanceData: any;
  setAppearanceData: React.Dispatch<React.SetStateAction<any>>;
  setTotalCost: (val: (prev: number) => number) => void;
}) {

  const handleNavigateBack = () => {
    if (navPath.length > 1) {
      const newPath = [...navPath];
      newPath.pop();
      setNavPath(newPath);
    }
  };

  const handleFeatureChange = (key: string, value: number) => {
    setTotalCost(prev => prev + 10);
    setAppearanceData((prev: any) => ({
      ...prev,
      faceFeatures: {
        ...(prev?.faceFeatures || {}),
        [key]: value
      }
    }));
    Nui.post('appearance_change_face_feature', { key, value });
  };

  const handleHeadBlendChange = (key: string, val: number) => {
    const currentBlend = appearanceData?.headBlend || {
      shapeFirst: 21,
      shapeSecond: 0,
      shapeThird: 0,
      skinFirst: 21,
      skinSecond: 0,
      skinThird: 0,
      shapeMix: 0.5,
      skinMix: 0.5,
      thirdMix: 0
    };
    const updated = { ...currentBlend, [key]: val };
    setTotalCost(prev => prev + 10);
    setAppearanceData((prev: any) => ({
      ...prev,
      headBlend: updated
    }));
    Nui.post('appearance_change_head_blend', updated);
  };

  const handleHeadOverlayChange = (key: string, value: any) => {
    setTotalCost(prev => prev + 50);
    const updatedOverlay = {
      style: value.style,
      opacity: value.opacity,
      color: value.color || 0,
      secondColor: value.secondColor || 0
    };
    setAppearanceData((prev: any) => ({
      ...prev,
      headOverlays: {
        ...(prev?.headOverlays || {}),
        [key]: updatedOverlay
      }
    }));
    Nui.post('appearance_change_head_overlay', {
       key, 
       style: value.style, 
       opacity: value.opacity, 
       color: value.color || 0, 
       secondColor: value.secondColor || 0
    });
  };

  const mainTab = navPath[0];
  let itemsToRender: string[] = [];
  
  if (mainTab === 'FACE ADJUSTMENTS') {
    if (activeCategory === 'NOSE') itemsToRender = ['noseWidth', 'nosePeakHigh', 'nosePeakSize', 'noseBoneHigh', 'nosePeakLowering', 'noseBoneTwist'];
    else if (activeCategory === 'BROW') itemsToRender = ['eyeBrownHigh', 'eyeBrownForward'];
    else if (activeCategory === 'EYES') itemsToRender = ['eyesOpening'];
    else if (activeCategory === 'CHEEKS') itemsToRender = ['cheeksBoneHigh', 'cheeksBoneWidth', 'cheeksWidth'];
    else if (activeCategory === 'LIPS & JAW' || activeCategory === 'LIPS') itemsToRender = ['lipsThickness', 'jawBoneWidth', 'jawBoneBackSize'];
    else if (activeCategory === 'CHIN & NECK' || activeCategory === 'CHIN') itemsToRender = ['chinBoneLowering', 'chinBoneLenght', 'chinBoneSize', 'chinHole', 'neckThickness'];
    else itemsToRender = ['noseWidth', 'nosePeakHigh', 'nosePeakSize', 'noseBoneHigh', 'nosePeakLowering', 'noseBoneTwist'];
  } else if (mainTab === 'OVERLAYS' || mainTab === 'HAIR') {
    if (activeCategory === 'BLEMISHES') itemsToRender = ['blemishes'];
    else if (activeCategory === 'AGEING') itemsToRender = ['ageing'];
    else if (activeCategory === 'COMPLEXION') itemsToRender = ['complexion'];
    else if (activeCategory === 'SUN DAMAGE') itemsToRender = ['sunDamage'];
    else if (activeCategory === 'MOLES & FRECKLES') itemsToRender = ['moleAndFreckles'];
    else if (activeCategory === 'BODY BLEMISHES') itemsToRender = ['bodyBlemishes'];
    else if (activeCategory === 'MAKEUP') itemsToRender = ['makeUp'];
    else if (activeCategory === 'BLUSH') itemsToRender = ['blush'];
    else if (activeCategory === 'LIPSTICK') itemsToRender = ['lipstick'];
    else if (activeCategory === 'FACIAL HAIR') itemsToRender = ['beard'];
    else if (activeCategory === 'EYEBROWS') itemsToRender = ['eyebrows'];
    else if (activeCategory === 'CHEST HAIR') itemsToRender = ['chestHair'];
    else itemsToRender = ['blemishes', 'ageing', 'complexion', 'sunDamage', 'moleAndFreckles', 'bodyBlemishes', 'makeUp', 'blush', 'lipstick', 'beard', 'eyebrows', 'chestHair'];
  } else if (mainTab === 'FACE & BODY' && activeCategory === 'HEAD BLEND') {
    itemsToRender = ['shapeFirst', 'shapeSecond', 'shapeMix', 'skinFirst', 'skinSecond', 'skinMix'];
  }

  const subcategoryList = SUBCATEGORIES_BY_TAB[mainTab] || [];

  return (
    <div className="w-[560px] flex flex-col pointer-events-auto ml-12 mt-8 select-none relative z-10 text-white">
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
        {/* Left Side Icon Navigation for subcategories */}
        {subcategoryList.length > 0 && (
          <div className="w-[52px] flex flex-col gap-[3px]">
            {subcategoryList.map(sub => {
              const isSubActive = activeCategory === sub.label || (navPath.length === 1 && sub.label === subcategoryList[0]?.label);
              return (
                <button 
                  key={sub.label}
                  title={sub.label}
                  onClick={() => {
                    setNavPath([mainTab, sub.label]);
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

        {/* Scrollable Container with max height bounded to viewport */}
        <div className="flex-1 bg-transparent p-0 flex flex-col gap-3.5 h-fit max-h-[72vh] overflow-y-auto styled-scrollbar">
          {itemsToRender.length === 0 && (
            <div className="text-xl font-oswald text-white/50 text-center py-10">NO OPTIONS AVAILABLE FOR {activeCategory}</div>
          )}
          
          {itemsToRender.map(key => {
            let value = 0;
            let min = -1.0;
            let max = 1.0;
            let step = 0.05;
            let isOverlay = false;
            let isHeadBlend = false;
            let isHeadBlendShapeOrSkin = false;

            if (mainTab === 'FACE ADJUSTMENTS') {
               value = appearanceData?.faceFeatures?.[key] || 0;
            } else if (mainTab === 'FACE & BODY' && activeCategory === 'HEAD BLEND') {
               isHeadBlend = true;
               value = appearanceData?.headBlend?.[key] ?? (key.includes('Mix') ? 0.5 : 0);
               if (key.includes('Mix')) {
                 min = 0.0; max = 1.0; step = 0.01;
               } else {
                 isHeadBlendShapeOrSkin = true;
                 min = 1; max = 46; step = 1;
               }
            } else if (mainTab === 'OVERLAYS' || mainTab === 'HAIR' || ['beard', 'eyebrows', 'chestHair', 'blemishes', 'ageing', 'complexion', 'sunDamage', 'moleAndFreckles', 'bodyBlemishes', 'makeUp', 'blush', 'lipstick'].includes(key)) {
               isOverlay = true;
               value = appearanceData?.headOverlays?.[key]?.style || 0;
               min = 0; max = 25; step = 1;
            }

            const currentDisplayVal = isHeadBlendShapeOrSkin ? Math.round(value) + 1 : value;

            const handleUpdate = (displayVal: number) => {
              const clampedDisplay = Math.min(Math.max(displayVal, min), max);
              if (isOverlay) {
                const currentOv = appearanceData?.headOverlays?.[key] || {};
                handleHeadOverlayChange(key, {
                  style: Math.round(clampedDisplay),
                  opacity: currentOv.opacity !== undefined ? currentOv.opacity : 1.0,
                  color: currentOv.color || 0,
                  secondColor: currentOv.secondColor || 0
                });
              } else if (isHeadBlend) {
                if (isHeadBlendShapeOrSkin) {
                  const internalVal = Math.round(clampedDisplay) - 1;
                  handleHeadBlendChange(key, internalVal);
                } else {
                  const finalVal = parseFloat(clampedDisplay.toFixed(2));
                  handleHeadBlendChange(key, finalVal);
                }
              } else {
                handleFeatureChange(key, parseFloat(clampedDisplay.toFixed(2)));
              }
            };

            const handleStep = (dir: number) => {
              let delta = 1;
              if (isHeadBlend && key.includes('Mix')) delta = 0.05;
              else if (!isHeadBlend && !isOverlay) delta = 0.05;
              handleUpdate(currentDisplayVal + dir * delta);
            };

            const displayValue = isHeadBlendShapeOrSkin 
              ? Math.round(currentDisplayVal)
              : isHeadBlend && key.includes('Mix')
              ? value.toFixed(2)
              : isOverlay 
              ? Math.round(value)
              : value.toFixed(2);

            const labelData = FEATURE_LABELS[key] || {
              title: (FEATURE_NAMES[key] || key.replace(/([A-Z])/g, ' $1')).toUpperCase(),
              minLabel: 'MIN',
              maxLabel: 'MAX'
            };

            const valToCalc = isHeadBlendShapeOrSkin ? currentDisplayVal : value;
            const pct = Math.min(Math.max(((valToCalc - min) / (max - min)) * 100, 0), 100);

            return (
              <div key={key} className="flex flex-col gap-1 shadow-md">
                {/* White Header Bar with Title on left & Value Badge + Steppers on right */}
                <div className="bg-white text-black font-oswald font-bold px-3 py-1 text-sm uppercase tracking-wider flex justify-between items-center">
                  <span>{labelData.title}</span>

                  <div className="flex items-center gap-1.5">
                    <button
                      type="button"
                      onClick={() => handleStep(-1)}
                      className="w-5 h-5 bg-black text-white hover:bg-zinc-800 font-bold flex items-center justify-center text-xs transition-colors cursor-pointer leading-none"
                      title="Decrease"
                    >
                      ‹
                    </button>
                    <span className="min-w-[36px] text-center font-oswald text-xs font-bold px-1.5 py-0.5 bg-black text-white leading-none">
                      {displayValue}
                    </span>
                    <button
                      type="button"
                      onClick={() => handleStep(1)}
                      className="w-5 h-5 bg-black text-white hover:bg-zinc-800 font-bold flex items-center justify-center text-xs transition-colors cursor-pointer leading-none"
                      title="Increase"
                    >
                      ›
                    </button>
                  </div>
                </div>

                {/* Slider Row Body */}
                <div className="bg-[#16181f]/95 p-3.5 border border-white/5 flex items-center justify-between gap-3">
                  <span className="font-bebas italic text-[17px] tracking-wider text-white/90 uppercase w-20 text-right flex-shrink-0">
                    {labelData.minLabel}
                  </span>

                  <input 
                    type="range" 
                    min={min} 
                    max={max} 
                    step={step} 
                    value={currentDisplayVal}
                    onChange={(e) => handleUpdate(parseFloat(e.target.value))}
                    className="flex-1 h-1.5 rounded-none appearance-none cursor-pointer"
                    style={{
                      background: `linear-gradient(to right, #ffffff ${pct}%, #3f3f46 ${pct}%)`
                    }}
                  />

                  <span className="font-bebas italic text-[17px] tracking-wider text-white/90 uppercase w-20 text-left flex-shrink-0">
                    {labelData.maxLabel}
                  </span>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
