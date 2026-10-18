import React from 'react';
import Nui from '../Nui';
import { getCategoryLucideIcon } from './CategoryIcons';

export default function Sidebar({ 
  navPath, 
  setNavPath, 
  categories 
}: { 
  navPath: string[], 
  setNavPath: (path: string[]) => void, 
  categories: any[] 
}) {
  const mainTab = navPath[0];

  const handleBack = () => {
    if (navPath.length > 1) {
      setNavPath(navPath.slice(0, -1));
    }
  };

  const handleSelect = (item: string) => {
    // Determine path based on if we are at root or inside a folder
    if (navPath.length === 1 && mainTab === 'APPAREL') {
      setNavPath([mainTab, item]);
    } else if (navPath.length === 2 && mainTab === 'APPAREL') {
      setNavPath([mainTab, navPath[1], item]);
    } else {
      setNavPath([mainTab, item]);
    }

  };

  return (
    <div className="w-[440px] flex flex-col pointer-events-auto ml-12 mt-8 select-none relative z-10">
      {/* Header / Breadcrumb - Fixed Height so it never jumps */}
      <div className="flex items-center gap-3.5 mb-4 h-12 whitespace-nowrap min-w-max">
        {navPath.length > 1 && (
          <button 
            onClick={handleBack}
            className="w-12 h-12 bg-white text-black font-bold text-2xl flex items-center justify-center hover:bg-zinc-200 transition-colors shadow-lg cursor-pointer flex-shrink-0"
            title="Go Back"
          >
            {'<'}
          </button>
        )}
        <div className="flex items-center gap-2 font-bebas italic text-[36px] tracking-wider uppercase leading-none pt-1 whitespace-nowrap">
          {navPath.map((seg, i) => {
            const isLast = i === navPath.length - 1;
            return (
              <React.Fragment key={i}>
                <span 
                  onClick={() => !isLast && setNavPath(navPath.slice(0, i + 1))}
                  className={`transition-colors whitespace-nowrap flex-shrink-0 ${isLast ? 'text-white font-bold' : 'text-white/40 hover:text-white cursor-pointer'}`}
                >
                  {seg}
                </span>
                {!isLast && <span className="text-white/20 select-none font-sans font-normal text-2xl">›</span>}
              </React.Fragment>
            );
          })}
        </div>
      </div>

      {/* Category List */}
      <div className="flex flex-col gap-[2px] max-h-[75vh] overflow-y-auto styled-scrollbar">
        {categories.map((itemObj: any) => {
          const item = itemObj.label;
          const isActive = navPath[navPath.length - 1] === item;
          return (
            <button key={item} 
              onClick={() => handleSelect(item)}
              className={`
                flex items-center w-full px-5 py-3.5 transition-colors group cursor-pointer
                ${isActive ? 'bg-white text-black' : 'bg-[#1a1c23]/95 text-white hover:bg-zinc-700'}
              `}>
              <div className="flex items-center gap-4">
                {getCategoryLucideIcon(item, `w-6 h-6 ${isActive ? 'text-black' : 'text-white'}`)}
                <span className={`font-oswald text-[20px] tracking-widest uppercase ${isActive ? 'font-bold' : 'opacity-90'}`}>
                  {item}
                </span>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
