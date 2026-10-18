import React, { useState } from 'react';
import { getTattooImage } from '../utils';

interface TattooImageProps {
  tattoo: { collection?: string; hashMale?: string; hashFemale?: string };
  gender?: 'male' | 'female';
}

// A tattoo's picture (thumbs/, see getTattooImage), else the tattoo icon over its collection's name - for a tattoo with
// no picture: one the game does not have, or a crew emblem (the player's crew's, made as the game runs).
export function TattooImage({ tattoo, gender }: TattooImageProps) {
  const src = getTattooImage(tattoo, gender);
  // (the address that failed: kept with it, the cell being reused for another tattoo)
  const [failed, setFailed] = useState('');

  if (src && failed !== src) {
    return <img src={src} onError={() => setFailed(src)} className="w-full h-full object-contain" />;
  }
  return (
    <div className="flex flex-col items-center justify-center gap-1.5 text-white/80 group-hover:text-white transition-colors p-2 text-center">
      <div className="w-10 h-10 rounded-full bg-white/10 border border-white/30 flex items-center justify-center text-white">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="w-5 h-5">
          <path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
        </svg>
      </div>
      <span className="text-[10px] font-oswald text-zinc-400 truncate max-w-[110px] uppercase">
        {tattoo.collection || 'Tattoo'}
      </span>
    </div>
  );
}
