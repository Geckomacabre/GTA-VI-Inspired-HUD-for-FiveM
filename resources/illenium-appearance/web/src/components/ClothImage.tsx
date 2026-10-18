import React, { useState } from 'react';
import { getClothImageCandidates } from '../utils';

const PLACEHOLDER = './files/faces/SKEL_ROOT.000.webp';

interface ClothImageProps {
  type: 'component' | 'prop';
  id: number;
  drawable: number;
  texture?: number;
  gender?: 'male' | 'female';
  className: string;
  placeholderClassName: string;
}

// An item's thumbnail: the first of its candidates there is (this server's own, then the public set), and the
// placeholder when there is none.
export function ClothImage({ type, id, drawable, texture = 0, gender, className, placeholderClassName }: ClothImageProps) {
  const candidates = React.useMemo(
    () => getClothImageCandidates(type, id, drawable, texture, gender),
    [type, id, drawable, texture, gender]
  );
  // (how far down the candidates this item is: kept with the item it is of, the cell being reused for another)
  const [tried, setTried] = useState({ item: '', at: 0 });
  const at = tried.item === candidates[0] ? tried.at : 0;
  const missing = at >= candidates.length;

  return (
    <img
      src={missing ? PLACEHOLDER : candidates[at]}
      onError={() => {
        if (!missing) setTried({ item: candidates[0], at: at + 1 });
      }}
      className={missing ? placeholderClassName : className}
    />
  );
}
