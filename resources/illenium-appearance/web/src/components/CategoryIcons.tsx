import React from 'react';
import { 
  Shirt, 
  Sparkles, 
  Watch, 
  Crown, 
  Glasses, 
  Footprints, 
  Backpack, 
  Tag, 
  Hand, 
  Gem, 
  Ghost, 
  Ear, 
  Layers, 
  Users, 
  Eye, 
  ScanFace, 
  Sliders, 
  Smile, 
  User, 
  CircleDot, 
  Hourglass, 
  Sun, 
  Heart, 
  Scissors, 
  Flame, 
  Paintbrush 
} from 'lucide-react';

export const LucidePants = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg 
    viewBox="0 0 24 24" 
    fill="none" 
    stroke="currentColor" 
    strokeWidth="2" 
    strokeLinecap="round" 
    strokeLinejoin="round" 
    className={className}
  >
    <path d="M4 2h16v3l-2 15h-4l-2-10-2 10H6L4 5z" />
  </svg>
);

// Authentic Tactical Bulletproof Kevlar Vest for Body Armor
export const LucideKevlarVest = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg 
    viewBox="0 0 24 24" 
    fill="none" 
    stroke="currentColor" 
    strokeWidth="2" 
    strokeLinecap="round" 
    strokeLinejoin="round" 
    className={className}
  >
    {/* Ballistic vest body */}
    <path d="M6 3h3.5l1.5 3h2l1.5-3H18l2 6-2 1v11H6V10L4 9z" />
    {/* Chest ballistic plate & MOLLE tactical webbing strips */}
    <path d="M8 12h8" />
    <path d="M8 16h8" />
  </svg>
);

// Tactical Chest Harness / Shoulder Holster Rig for Upper Body Accessories
export const LucideTacticalHarness = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg 
    viewBox="0 0 24 24" 
    fill="none" 
    stroke="currentColor" 
    strokeWidth="2" 
    strokeLinecap="round" 
    strokeLinejoin="round" 
    className={className}
  >
    {/* Dual shoulder straps */}
    <path d="M6 3v5l-2 4v9" />
    <path d="M18 3v5l2 4v9" />
    {/* Chest webbing with center buckle */}
    <path d="M6 9h12" />
    <path d="M6 14h12" />
    <circle cx="12" cy="11.5" r="2" />
    <path d="M12 13.5v7.5" />
  </svg>
);

export const IconFaceNose = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <path d="M12 4v8l4 4" />
    <path d="M8 16h8" />
  </svg>
);

export const IconFaceBrow = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <rect x="5" y="5" width="14" height="14" rx="2" />
    <circle cx="12" cy="12" r="2" />
    <path d="M12 7v2" />
    <path d="M12 15v2" />
    <path d="M7 12h2" />
    <path d="M15 12h2" />
  </svg>
);

export const IconFaceEyes = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z" />
    <circle cx="12" cy="12" r="3" />
  </svg>
);

export const IconFaceCheeks = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <circle cx="12" cy="12" r="9" />
    <circle cx="8" cy="13" r="1.5" />
    <circle cx="16" cy="13" r="1.5" />
  </svg>
);

export const IconFaceLips = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <path d="M6 11c2-2 4-2 6-1 2-1 4-1 6 1-2 4-10 4-12 0z" />
    <path d="M6 11c2 1 4 3 6 3s4-2 6-3" />
  </svg>
);

export const IconFaceChin = ({ className = 'w-6 h-6' }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <path d="M7 4h10v6c0 4.5-3.5 8-8 8s-8-3.5-8-8V4z" />
    <path d="M10 18h4" />
  </svg>
);

export const getCategoryLucideIcon = (label: string, className: string = 'w-6 h-6') => {
  const l = (label || '').toUpperCase().trim();

  // Apparel Parent Categories
  if (l === 'OUTFITS' || l === 'SAVED OUTFITS') return <Layers className={className} />;
  if (l === 'CLOTHING') return <Shirt className={className} />;
  if (l === 'UPPER BODY ACCESSORIES') return <LucideTacticalHarness className={className} />;
  if (l === 'HAND & WRIST ACCESSORIES') return <Watch className={className} />;
  if (l === 'HEAD ACCESSORIES') return <Crown className={className} />;

  // Clothing subcategories
  if (l.includes('TOP')) return <Shirt className={className} />;
  if (l.includes('BOTTOM') || l.includes('LEG')) return <LucidePants className={className} />;
  if (l.includes('SHOE') || l.includes('FOOT')) return <Footprints className={className} />;

  // Upper body accessories
  if (l.includes('ARMOR')) return <LucideKevlarVest className={className} />;
  if (l.includes('BAG') || l.includes('PARACHUTE')) return <Backpack className={className} />;
  if (l.includes('DECAL')) return <Tag className={className} />;

  // Hand & wrist accessories
  if (l.includes('GLOVE')) return <Hand className={className} />;
  if (l.includes('WATCH')) return <Watch className={className} />;
  if (l.includes('BRACELET')) return <Gem className={className} />;

  // Head accessories
  if (l.includes('MASK')) return <Ghost className={className} />;
  if (l.includes('HAT')) return <Crown className={className} />;
  if (l.includes('GLASS')) return <Glasses className={className} />;
  if (l.includes('EAR')) return <Ear className={className} />;

  // Face & Body
  if (l.includes('HEAD BLEND') || l.includes('BLEND')) return <Users className={className} />;
  if (l.includes('EYE COLOR')) return <IconFaceEyes className={className} />;
  if (l.includes('FEATURE') || l.includes('FACE')) return <ScanFace className={className} />;

  // Face Adjustments
  if (l.includes('NOSE')) return <IconFaceNose className={className} />;
  if (l.includes('BROW')) return <IconFaceBrow className={className} />;
  if (l.includes('EYE')) return <IconFaceEyes className={className} />;
  if (l.includes('CHEEK')) return <IconFaceCheeks className={className} />;
  if (l.includes('LIP') || l.includes('JAW')) return <IconFaceLips className={className} />;
  if (l.includes('CHIN') || l.includes('NECK')) return <IconFaceChin className={className} />;

  // Overlays
  if (l.includes('BLEMISH') || l.includes('MOLE') || l.includes('FRECKLE')) return <CircleDot className={className} />;
  if (l.includes('AGE')) return <Hourglass className={className} />;
  if (l.includes('COMPLEXION') || l.includes('SUN')) return <Sun className={className} />;
  if (l.includes('MAKEUP')) return <Sparkles className={className} />;
  if (l.includes('BLUSH') || l.includes('LIPSTICK')) return <Heart className={className} />;
  if (l.includes('FACIAL HAIR') || l.includes('HAIR') || l.includes('STYLE')) return <Scissors className={className} />;
  if (l.includes('CHEST')) return <User className={className} />;

  // Tattoos
  if (l.includes('HEAD') || l.includes('TORSO')) return <Flame className={className} />;
  if (l.includes('ARM') || l.includes('LEG')) return <Paintbrush className={className} />;

  // Ped & Models
  if (l.includes('PED') || l.includes('MODEL')) return <User className={className} />;

  return <Shirt className={className} />;
};
