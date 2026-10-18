import React from 'react';

export default function EconomyWidget({ cash, bank }: { cash: number, bank: number }) {
  return (
    <div className="flex gap-1.5 font-oswald font-bold text-[17px] tracking-wide shadow-2xl pointer-events-auto select-none">
      <div className="flex items-center bg-[#00f0ff] text-black px-4 py-1 gap-1.5 min-w-[120px] justify-center">
        <span className="text-[19px] leading-none">$</span>
        <span className="mt-[2px]">{cash.toLocaleString()}</span>
      </div>
      <div className="flex items-center bg-[#00c8ff] text-black px-4 py-1 gap-2 min-w-[120px] justify-center">
        <svg viewBox="0 0 24 24" fill="currentColor" width="16" height="16" className="flex-shrink-0">
          <path d="M12 2L2 7H22L12 2ZM2 9V20H4V9H2ZM6 9V20H8V9H6ZM10 9V20H12V9H10ZM14 9V20H16V9H14ZM18 9V20H20V9H18ZM2 22H22V24H2V22Z" />
        </svg>
        <span className="mt-[2px]">{bank.toLocaleString()}</span>
      </div>
    </div>
  );
}
