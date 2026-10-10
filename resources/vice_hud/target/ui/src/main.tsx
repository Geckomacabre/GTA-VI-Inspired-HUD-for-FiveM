import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import * as Host from './host'
import App from './App'
import './styles/base.css' // UNLAYERED CEF transparency - must load before HeroUI/index.css
import './styles/index.css'

// Publish design SDK: exposes React, icons, and helper utilities on window global for modular packs.
window.OsmTargetHost = Host

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
