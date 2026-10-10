import {
  AddressBookIcon, AirplaneIcon, AnchorIcon, ArchiveIcon, ArrowDownIcon, ArrowLeftIcon, ArrowRightIcon, ArrowUpIcon,
  ArrowsClockwiseIcon, BackpackIcon, BankIcon, BarcodeIcon, BatteryChargingIcon, BedIcon, BeerBottleIcon, BellIcon,
  BicycleIcon, BoatIcon, BombIcon, BookOpenIcon, BooksIcon, BroadcastIcon, BugIcon, BuildingsIcon,
  CalculatorIcon, CalendarIcon, CameraIcon, CarIcon, CaretLeftIcon, CaretRightIcon, CashRegisterIcon, ChatCircleIcon,
  CheckIcon, CigaretteIcon, CircleIcon, CityIcon, ClipboardTextIcon, ClockIcon, CodeIcon, CoffeeIcon,
  CoinsIcon, CompassIcon, CreditCardIcon, CrosshairIcon, CubeIcon, CurrencyDollarIcon, DatabaseIcon, DetectiveIcon,
  DeviceMobileIcon, DiamondIcon, DogIcon, DoorIcon, DoorOpenIcon, DotsThreeIcon, DropIcon, EngineIcon,
  EraserIcon, EyeIcon, EyeglassesIcon, FireIcon, FirstAidIcon, FirstAidKitIcon, FishIcon, FloppyDiskIcon,
  FolderIcon, ForkKnifeIcon, GasPumpIcon, GavelIcon, GearIcon, GearSixIcon, GlobeIcon, HammerIcon,
  HandCoinsIcon, HandPalmIcon, HandshakeIcon, HashIcon, HeartIcon, HeartbeatIcon, HourglassIcon, HouseIcon,
  InfoIcon, KeyIcon, KeyboardIcon, KnifeIcon, LeafIcon, LightbulbIcon, LightningIcon, ListIcon,
  LockIcon, LockKeyIcon, LockOpenIcon, MagnifyingGlassIcon, MapPinIcon, MinusIcon, MoonIcon, MotorcycleIcon,
  NavigationArrowIcon, NewspaperIcon, NoteIcon, NotePencilIcon, PackageIcon, PaintBrushIcon, PaletteIcon, PersonIcon,
  PhoneIcon, PillIcon, PizzaIcon, PlugIcon, PlusIcon, PrinterIcon, ProhibitIcon, QrCodeIcon,
  RadioIcon, ReceiptIcon, RecycleIcon, ScalesIcon, ScissorsIcon, ScrewdriverIcon, SealCheckIcon, ShieldIcon,
  ShieldCheckIcon, ShieldWarningIcon, ShoppingBagIcon, ShoppingCartIcon, SignInIcon, SkullIcon, SparkleIcon, StarIcon,
  StethoscopeIcon, StorefrontIcon, SuitcaseIcon, SunIcon, SyringeIcon, TShirtIcon, TagIcon, TargetIcon,
  TaxiIcon, TerminalIcon, TicketIcon, TimerIcon, ToolboxIcon, TrashIcon, TreeIcon, TrophyIcon,
  TruckIcon, UsbIcon, UserCircleIcon, UsersIcon, VaultIcon, WarningIcon, WindIcon, WineIcon,
  WrenchIcon, XIcon,
} from '@phosphor-icons/react'

import type { Icon as PhosphorIcon, IconWeight } from '@phosphor-icons/react'

export type { IconWeight }

/** Curated Phosphor icon registry mapped by lowercase kebab identifiers. */
export const ICONS: Record<string, PhosphorIcon> = {
  // vehicles
  car: CarIcon, truck: TruckIcon, motorcycle: MotorcycleIcon, bicycle: BicycleIcon, boat: BoatIcon,
  airplane: AirplaneIcon, engine: EngineIcon, fuel: GasPumpIcon, trunk: PackageIcon, door: DoorIcon,
  'door-open': DoorOpenIcon, wheel: GearIcon, anchor: AnchorIcon,

  // tools & crime
  wrench: WrenchIcon, toolbox: ToolboxIcon, hammer: HammerIcon, screwdriver: ScrewdriverIcon,
  lockpick: LockKeyIcon, lock: LockIcon, unlock: LockOpenIcon, key: KeyIcon, knife: KnifeIcon,
  crosshair: CrosshairIcon, skull: SkullIcon, target: TargetIcon,

  // commerce
  shop: StorefrontIcon, cart: ShoppingCartIcon, bag: ShoppingBagIcon, cash: CurrencyDollarIcon,
  card: CreditCardIcon, bank: BankIcon, coins: CoinsIcon, receipt: ReceiptIcon, tag: TagIcon,
  barcode: BarcodeIcon, qr: QrCodeIcon, ticket: TicketIcon,

  // food & drink
  food: ForkKnifeIcon, coffee: CoffeeIcon, beer: BeerBottleIcon, wine: WineIcon, pizza: PizzaIcon,
  cigarette: CigaretteIcon, water: DropIcon,

  // medical
  medkit: FirstAidKitIcon, bandage: FirstAidIcon, pill: PillIcon, syringe: SyringeIcon, heartbeat: HeartbeatIcon,

  // people
  person: PersonIcon, people: UsersIcon, profile: UserCircleIcon, handshake: HandshakeIcon,
  chat: ChatCircleIcon, phone: PhoneIcon, mobile: DeviceMobileIcon, radio: RadioIcon, broadcast: BroadcastIcon,

  // law
  shield: ShieldIcon, 'shield-check': ShieldCheckIcon, 'shield-warning': ShieldWarningIcon,
  scales: ScalesIcon, gavel: GavelIcon, prohibit: ProhibitIcon, verified: SealCheckIcon,

  // utility
  fire: FireIcon, power: LightningIcon, plug: PlugIcon, battery: BatteryChargingIcon,
  paint: PaintBrushIcon, palette: PaletteIcon, camera: CameraIcon, eye: EyeIcon, search: MagnifyingGlassIcon,
  pin: MapPinIcon, navigate: NavigationArrowIcon, compass: CompassIcon, clock: ClockIcon,
  calendar: CalendarIcon, note: NoteIcon, clipboard: ClipboardTextIcon, folder: FolderIcon,
  save: FloppyDiskIcon, trash: TrashIcon, printer: PrinterIcon, terminal: TerminalIcon, code: CodeIcon,
  database: DatabaseIcon, books: BooksIcon, book: BookOpenIcon, news: NewspaperIcon, bug: BugIcon,

  // objects & places
  box: CubeIcon, case: SuitcaseIcon, backpack: BackpackIcon, clothes: TShirtIcon, scissors: ScissorsIcon,
  bed: BedIcon, house: HouseIcon, building: BuildingsIcon, tree: TreeIcon, leaf: LeafIcon, fish: FishIcon,
  dog: DogIcon, sun: SunIcon, moon: MoonIcon, wind: WindIcon, trophy: TrophyIcon, gem: DiamondIcon,
  sparkle: SparkleIcon, star: StarIcon, heart: HeartIcon,

  // controls
  plus: PlusIcon, minus: MinusIcon, close: XIcon, check: CheckIcon, list: ListIcon, more: DotsThreeIcon,
  settings: GearSixIcon, refresh: ArrowsClockwiseIcon, info: InfoIcon, warning: WarningIcon,
  'arrow-left': ArrowLeftIcon, 'arrow-right': ArrowRightIcon, 'arrow-up': ArrowUpIcon,
  'arrow-down': ArrowDownIcon, 'caret-left': CaretLeftIcon, 'caret-right': CaretRightIcon,

  'address-book': AddressBookIcon,
  archive: ArchiveIcon,
  bell: BellIcon,
  bomb: BombIcon,
  calculator: CalculatorIcon,
  'cash-register': CashRegisterIcon,
  circle: CircleIcon,
  city: CityIcon,
  detective: DetectiveIcon,
  eraser: EraserIcon,
  glasses: EyeglassesIcon,
  eyeglasses: EyeglassesIcon,
  globe: GlobeIcon,
  'hand-coins': HandCoinsIcon,
  'hand-palm': HandPalmIcon,
  hash: HashIcon,
  hourglass: HourglassIcon,
  keyboard: KeyboardIcon,
  lightbulb: LightbulbIcon,
  'note-pencil': NotePencilIcon,
  recycle: RecycleIcon,
  'sign-in': SignInIcon,
  stethoscope: StethoscopeIcon,
  stopwatch: TimerIcon,
  timer: TimerIcon,
  taxi: TaxiIcon,
  usb: UsbIcon,
  vault: VaultIcon,
  safe: VaultIcon,
}

/** FontAwesome to bundled equivalents, keyed by the bare fa name: `fas fa-car`,
 *  `fa-solid fa-car` and `car` all land in the same place. */
const FA_ALIASES: Record<string, string> = {
  car: 'car', 'car-side': 'car', 'car-battery': 'battery', truck: 'truck',
  motorcycle: 'motorcycle', bicycle: 'bicycle', ship: 'boat', plane: 'airplane',
  'gas-pump': 'fuel', 'oil-can': 'fuel', 'door-closed': 'door', 'door-open': 'door-open',
  'box-open': 'trunk', warehouse: 'building',

  wrench: 'wrench', screwdriver: 'screwdriver', hammer: 'hammer', toolbox: 'toolbox',
  'screwdriver-wrench': 'toolbox', tools: 'toolbox', key: 'key', lock: 'lock',
  'lock-open': 'unlock', unlock: 'unlock', 'user-lock': 'lock', crosshairs: 'crosshair',
  skull: 'skull', 'skull-crossbones': 'skull', bullseye: 'target',

  store: 'shop', 'store-alt': 'shop', 'shopping-cart': 'cart', 'shopping-basket': 'cart',
  'shopping-bag': 'bag', 'dollar-sign': 'cash', 'money-bill': 'cash',
  'money-bill-wave': 'cash', 'credit-card': 'card', 'university': 'bank',
  'piggy-bank': 'bank', coins: 'coins', receipt: 'receipt', tag: 'tag', tags: 'tag',
  barcode: 'barcode', qrcode: 'qr', ticket: 'ticket', 'ticket-alt': 'ticket',

  utensils: 'food', hamburger: 'food', burger: 'food', pizza: 'pizza',
  'pizza-slice': 'pizza', mug: 'coffee', 'mug-hot': 'coffee', coffee: 'coffee',
  'beer-mug-empty': 'beer', beer: 'beer', 'wine-glass': 'wine', 'wine-bottle': 'wine',
  smoking: 'cigarette', 'glass-water': 'water', droplet: 'water', tint: 'water',

  'kit-medical': 'medkit', 'briefcase-medical': 'medkit', 'medkit': 'medkit',
  'first-aid': 'bandage', bandage: 'bandage', pills: 'pill', prescription: 'pill',
  syringe: 'syringe', 'heart-pulse': 'heartbeat', heartbeat: 'heartbeat',

  user: 'person', users: 'people', 'user-circle': 'profile', 'user-friends': 'people',
  handshake: 'handshake', comment: 'chat', comments: 'chat', 'comment-dots': 'chat',
  phone: 'phone', 'mobile-alt': 'mobile', 'mobile-screen': 'mobile',
  'walkie-talkie': 'radio', broadcast: 'broadcast', 'tower-broadcast': 'broadcast',

  shield: 'shield', 'shield-alt': 'shield', 'shield-halved': 'shield',
  'user-shield': 'shield-check', 'shield-check': 'shield-check',
  'balance-scale': 'scales', gavel: 'gavel', ban: 'prohibit',
  'circle-check': 'verified', 'check-circle': 'verified',

  fire: 'fire', 'fire-flame-curved': 'fire', bolt: 'power', 'plug': 'plug',
  'battery-full': 'battery', 'charging-station': 'battery',
  'paint-brush': 'paint', 'spray-can': 'paint', palette: 'palette',
  camera: 'camera', 'video': 'camera', eye: 'eye', 'magnifying-glass': 'search',
  search: 'search', 'map-marker-alt': 'pin', 'location-dot': 'pin', 'map-pin': 'pin',
  'location-arrow': 'navigate', compass: 'compass', clock: 'clock',
  'calendar-alt': 'calendar', 'sticky-note': 'note', 'clipboard': 'clipboard',
  'clipboard-list': 'clipboard', folder: 'folder', 'folder-open': 'folder',
  'floppy-disk': 'save', save: 'save', 'trash-alt': 'trash', trash: 'trash',
  print: 'printer', terminal: 'terminal', code: 'code', database: 'database',
  book: 'book', 'book-open': 'book', newspaper: 'news', bug: 'bug',

  box: 'box', boxes: 'box', cube: 'box', cubes: 'box', 'briefcase': 'case',
  suitcase: 'case', backpack: 'backpack', 'suitcase-rolling': 'case',
  'shirt': 'clothes', tshirt: 'clothes', scissors: 'scissors', cut: 'scissors',
  bed: 'bed', home: 'house', house: 'house', building: 'building', tree: 'tree',
  leaf: 'leaf', cannabis: 'leaf', fish: 'fish', dog: 'dog', sun: 'sun', moon: 'moon',
  wind: 'wind', trophy: 'trophy', gem: 'gem', diamond: 'gem', star: 'star',
  heart: 'heart', sparkles: 'sparkle', 'wand-magic-sparkles': 'sparkle',

  plus: 'plus', minus: 'minus', times: 'close', xmark: 'close', check: 'check',
  bars: 'list', list: 'list', 'list-ul': 'list', 'ellipsis-h': 'more', cog: 'settings',
  gear: 'settings', gears: 'settings', 'sync-alt': 'refresh', 'rotate-right': 'refresh',
  'info-circle': 'info', 'circle-info': 'info', 'exclamation-triangle': 'warning',
  'triangle-exclamation': 'warning', 'circle-chevron-left': 'arrow-left',
  'arrow-left': 'arrow-left', 'arrow-right': 'arrow-right', 'chevron-left': 'caret-left',
  'chevron-right': 'caret-right', 'arrow-up': 'arrow-up', 'arrow-down': 'arrow-down',

  'address-book': 'address-book',
  'box-archive': 'archive',
  'cash-register': 'cash-register',
  'circle-plus': 'plus',
  'circle-xmark': 'close',
  'angle-left': 'caret-left',
  'caret-up': 'arrow-up',
  'globe': 'globe',
  'handcuffs': 'handcuffs',
  'hand-holding-dollar': 'hand-coins',
  'hand-point-down': 'hand-point-down',
  'hand-point-up': 'hand-point-up',
  'hourglass-start': 'hourglass',
  'hourglass-half': 'hourglass',
  'hourglass-end': 'hourglass',
  'laptop-code': 'laptop-code',
  'stethoscope': 'stethoscope',
  'user-secret': 'detective',
  'hand-holding': 'hand-palm',
  'hashtag': 'hash',
  'pen-to-square': 'note-pencil',
  'right-to-bracket': 'sign-in',
  'user-large-slash': 'user-slash',
  'bell': 'bell',
  'bottle-droplet': 'water',
  'building-shield': 'shield',
  'calculator': 'calculator',
  'calendar-days': 'calendar',
  'campground': 'house',
  'car-burst': 'car',
  'car-rear': 'car',
  'chair': 'bed',
  'child': 'person',
  'circle-exclamation': 'warning',
  'circle-user': 'profile',
  'duck': 'fish',
  'ear-deaf': 'prohibit',
  'edit': 'note',
  'eye-slash': 'eye',
  'keyboard': 'keyboard',
  'people-carry': 'people',
  'people-pulling': 'people',
  'person-hiking': 'person',
  'person-running': 'person',
  'person-walking': 'person',
  'person-walking-with-cane': 'person',
  'file-invoice-dollar': 'receipt',
  'glasses': 'glasses',
  'hand': 'hand-palm',
  'hat-cowboy-side': 'profile',
  'lightbulb': 'lightbulb',
  'list-check': 'list',
  'mask': 'profile',
  'masks-theater': 'profile',
  'mitten': 'hand-palm',
  'rectangle-list': 'list',
  'road': 'navigate',
  'shoe-prints': 'person',
  'sign-hanging': 'tag',
  'stopwatch': 'stopwatch',
  'toggle-on': 'check',
  'torii-gate': 'building',
  'truck-pickup': 'truck',
  'user-doctor': 'person',
  'user-group': 'people',
  'user-pen': 'person',
  'user-tie': 'person',
  'vest': 'clothes',
  'city': 'city',
  'eraser': 'eraser',
  'recycle': 'recycle',
  'tape': 'tape',
  'taxi': 'taxi',
  'vault': 'safe',
  'usb': 'usb',
  'bomb': 'bomb',
  'faucet': 'faucet',
  'ring': 'ring',
}

/** Resolve any icon reference - bundled id, FontAwesome class, bare fa name. */
export function resolveIcon(name?: string): PhosphorIcon | null {
  if (!name) return null

  const direct = ICONS[name]
  if (direct) return direct

  // "fas fa-car" / "fa-solid fa-car" / "fa-car" -> "car"
  const parts = name.toLowerCase().trim().split(/\s+/)
  for (const part of parts) {
    const bare = part.replace(/^fa[srbldt]?-/, '').replace(/^fa-/, '')
    const alias = FA_ALIASES[bare]
    if (alias && ICONS[alias]) return ICONS[alias]
    if (ICONS[bare]) return ICONS[bare]
  }

  return null
}

interface OptionIconProps {
  name?: string
  size: number
  weight?: IconWeight
  color?: string
  className?: string
}

/** Falls back to a neutral dot: a legacy resource with an icon we do not carry
 *  should lose the glyph, never the row. */
export function OptionIcon({ name, size, weight = 'bold', color, className }: OptionIconProps) {
  const Glyph = resolveIcon(name)

  if (!Glyph) {
    return (
      <span
        className={className}
        style={{
          width: size * 0.42,
          height: size * 0.42,
          borderRadius: '50%',
          background: color ?? 'currentColor',
          opacity: 0.55,
          display: 'block',
          margin: size * 0.29,
        }}
      />
    )
  }

  return <Glyph size={size} weight={weight} color={color} className={className} />
}
