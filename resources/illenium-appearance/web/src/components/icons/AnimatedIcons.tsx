import React from 'react';
import {
  Mouse,
  RotateCcw,
  ZoomIn,
  Move,
  CornerDownLeft,
  ShoppingCart,
  X,
} from 'lucide-react';

const cls = 'w-4 h-4 shrink-0';

export function MouseIcon() {
  return (
    <span style={{ display: 'inline-flex', animation: 'mouse-scroll 1.2s ease-in-out infinite' }}>
      <Mouse className={cls} />
      <style>{`@keyframes mouse-scroll { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-2px)} }`}</style>
    </span>
  );
}

export function RotateCcwIcon() {
  return (
    <span style={{ display: 'inline-flex' }} className="hover-rotate">
      <RotateCcw className={cls} />
      <style>{`.hover-rotate:hover svg { animation: spin-once 0.5s ease-in-out; } @keyframes spin-once { from{transform:rotate(0deg)} to{transform:rotate(-360deg)} }`}</style>
    </span>
  );
}

export function ZoomInIcon() {
  return (
    <span style={{ display: 'inline-flex', animation: 'pulse-zoom 1.5s ease-in-out infinite' }}>
      <ZoomIn className={cls} />
      <style>{`@keyframes pulse-zoom { 0%,100%{transform:scale(1)} 50%{transform:scale(1.15)} }`}</style>
    </span>
  );
}

export function MoveIcon() {
  return (
    <span style={{ display: 'inline-flex' }}>
      <Move className={cls} />
    </span>
  );
}

export function CornerDownLeftIcon() {
  return (
    <span style={{ display: 'inline-flex' }}>
      <CornerDownLeft className={cls} />
    </span>
  );
}

export function ShoppingCartIcon() {
  return (
    <span style={{ display: 'inline-flex', animation: 'cart-bounce 1.8s ease-in-out infinite' }}>
      <ShoppingCart className={cls} />
      <style>{`@keyframes cart-bounce { 0%,100%{transform:translateX(0)} 50%{transform:translateX(2px)} }`}</style>
    </span>
  );
}

export function XIcon() {
  return (
    <span style={{ display: 'inline-flex' }}>
      <X className={cls} />
    </span>
  );
}

