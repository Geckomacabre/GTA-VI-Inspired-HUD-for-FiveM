import React from 'react';

export const IconTShirt = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M7 5L12 7L17 5L21 9L18 11V21H6V11L3 9L7 5Z" />
  </svg>
);

export const IconPants = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M4 2H20L19 10H14V22H9V10H5L4 2Z" />
  </svg>
);

export const IconShoes = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M4 18V20H20V18C18 16 16 14 16 10H8C8 14 6 16 4 18Z" />
  </svg>
);

export const IconUpperBody = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M7 6L12 8L17 6L19 12L15 15V20H9V15L5 12L7 6Z" opacity="0.5"/>
    <circle cx="12" cy="12" r="3" fill="currentColor" />
  </svg>
);

export const IconGloves = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M7 16V9C7 7.89 7.89 7 9 7C10.1 7 11 7.89 11 9V16" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
    <path d="M11 16V6C11 4.89 11.89 4 13 4C14.1 4 15 4.89 15 6V16" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
    <path d="M15 16V8C15 6.89 15.89 6 17 6C18.1 6 19 6.89 19 8V16" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
    <path d="M7 13V11C7 9.89 6.1 9 5 9C3.89 9 3 9.89 3 11V16C3 18.2 4.79 20 7 20H15C17.2 20 19 18.2 19 16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" fill="none"/>
  </svg>
);

export const IconHat = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M3 15C3 16.1 3.9 17 5 17H19C20.1 17 21 16.1 21 15V13H3V15ZM12 4C8.13 4 5 7.13 5 11H19C19 7.13 15.87 4 12 4Z" />
  </svg>
);

export const IconWatch = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M12,2A10,10 0 0,0 2,12A10,10 0 0,0 12,22A10,10 0 0,0 22,12A10,10 0 0,0 12,2M12,20A8,8 0 0,1 4,12A8,8 0 0,1 12,4A8,8 0 0,1 20,12A8,8 0 0,1 12,20M12.5,7H11V13L16.2,16.2L17,14.9L12.5,12.2V7Z" />
  </svg>
);

export const IconBag = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M16 6V4C16 2.89 15.11 2 14 2H10C8.89 2 8 2.89 8 4V6H2V22H22V6H16ZM10 4H14V6H10V4ZM20 20H4V8H20V20Z" />
  </svg>
);

export const IconFilter = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M3 4C3 3.44772 3.44772 3 4 3H20C20.5523 3 21 3.44772 21 4V6.58579C21 7.11622 20.7893 7.62493 20.4142 8L14 14.4142V21C14 21.5523 13.5523 22 13 22H11C10.4477 22 10 21.5523 10 21V14.4142L3.58579 8C3.21071 7.62493 3 7.11622 3 6.58579V4Z" />
  </svg>
);

export const IconCheck = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" className={className}>
    <path d="M5 13L9 17L19 7" strokeLinecap="round" strokeLinejoin="round" />
  </svg>
);

export const IconUndress = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={className}>
    <path d="M7 5L12 7L17 5L21 9L18 11V21H6V11L3 9L7 5Z" />
    <line x1="3" y1="3" x2="21" y2="21" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
  </svg>
);

export const IconGlasses = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M6 8C3.79 8 2 9.79 2 12C2 14.21 3.79 16 6 16C7.96 16 9.57 14.59 9.93 12.75C10.45 13.06 11.19 13.25 12 13.25C12.81 13.25 13.55 13.06 14.07 12.75C14.43 14.59 16.04 16 18 16C20.21 16 22 14.21 22 12C22 9.79 20.21 8 18 8C15.79 8 14 9.79 14 12H10C10 9.79 8.21 8 6 8ZM6 10C7.1 10 8 10.9 8 12C8 13.1 7.1 14 6 14C4.9 14 4 13.1 4 12C4 10.9 4.9 10 6 10ZM18 10C19.1 10 20 10.9 20 12C20 13.1 19.1 14 18 14C16.9 14 16 13.1 16 12C16 10.9 16.9 10 18 10Z"/>
  </svg>
);

export const IconMask = ({ className }: { className?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" className={className}>
    <path d="M12 2C6.48 2 2 6.48 2 12C2 16.5 5 20.3 9.1 21.6C9.6 21.8 10 21.4 10 20.9V19.1C6.7 19.8 6 17.5 6 17.5C5.5 16.2 4.7 15.8 4.7 15.8C3.6 15.1 4.8 15.1 4.8 15.1C6 15.2 6.6 16.3 6.6 16.3C7.7 18.2 9.5 17.6 10.2 17.3C10.3 16.5 10.6 15.9 11 15.6C8.4 15.3 5.6 14.3 5.6 9.8C5.6 8.5 6.1 7.5 6.9 6.7C6.8 6.4 6.4 5.2 7 3.6C7 3.6 8 3.3 10.3 4.8C11.3 4.5 12.3 4.4 13.3 4.4C14.3 4.4 15.3 4.5 16.3 4.8C18.6 3.3 19.6 3.6 19.6 3.6C20.2 5.2 19.8 6.4 19.7 6.7C20.5 7.5 21 8.5 21 9.8C21 14.3 18.2 15.3 15.6 15.6C16.1 16 16.5 16.8 16.5 18V20.9C16.5 21.4 16.9 21.8 17.4 21.6C21.5 20.3 24.5 16.5 24.5 12C24.5 6.48 20.02 2 14.5 2H12Z" />
  </svg>
);

