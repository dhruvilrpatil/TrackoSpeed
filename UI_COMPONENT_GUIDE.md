# TrackoSpeed UI Component Guide

## Dashboard Page Components

### 1. Header Component
```
┌─────────────────────────────────────┐
│  Dashboard                    [⚙️]  │
│  ● GPS Active                       │
└─────────────────────────────────────┘
```
- Title: "Dashboard" (28px, bold, dark text)
- GPS Indicator: Green/Red dot + status text
- Settings button: Circular white background with teal icon

### 2. View Toggle
```
┌─────────────────────────────────────┐
│ ┌────────────────────────────────┐  │
│ │[Digital] │ Map │ AR Mode       │  │
│ └────────────────────────────────┘  │
└─────────────────────────────────────┘
```
- Container: White 70% opacity, 30px border radius
- Selected: White background with shadow
- Unselected: Transparent background
- Text: 14px, bold when selected

### 3. Circular Speedometer
```
     ╭─────────────────╮
   ╱                     ╲
  │    ╭───────────╮      │
  │   │            │      │
 │    │    105     │       │
 │    │            │       │
 │    │   KM/H     │       │
  │   │            │      │
  │    ╰───────────╯      │
   ╲                     ╱
     ╰─────────────────╯
```
- Size: 280x280px
- Stroke: 16px teal color
- Background: 30% white opacity
- Speed text: 80px, bold, dark text
- Unit text: 18px, teal, uppercase

### 4. Statistics Cards
```
┌──────┐  ┌──────┐  ┌──────┐
│  🏃  │  │  ⬆️  │  │  📈  │
│ AVG  │  │ MAX  │  │ DIST │
│  45  │  │ 120  │  │ 12.5 │
└──────┘  └──────┘  └──────┘
```
- Background: White 80% opacity
- Border radius: 20px
- Icon: 28px, teal 70% opacity
- Label: 12px, dark 60% opacity
- Value: 24px, bold, dark text
- Spacing: 12px between cards

### 5. Tracking Button
```
┌─────────────────────────────────┐
│  ▶️  Start Tracking              │
└─────────────────────────────────┘
```
- Width: Full width (with 20px padding)
- Height: 18px padding vertical
- Background: Teal with 40% opacity shadow
- Border radius: 30px
- Icon: 28px white
- Text: 18px, bold, white

## Camera Mode Page Components

### 1. Top Header (Overlay)
```
[X]     🧭 GPS Active     NW 315°
```
- Close button: 44x44px, 50% black circle
- GPS icon: 16px, success green
- Text: 14px, white, medium weight
- Spacing: Centered with 30px gap

### 2. Vehicle Speed Card
```
┌──────────────┐
│ VEHICLE      │
│              │
│ 74  KPH      │
│              │
│ 45m DIST     │
└──────────────┘
```
- Background: Black 60% opacity
- Border: White 30% opacity, 1px
- Border radius: 16px
- Padding: 16px
- Position: top: 120px, right: 20px
- Label: 11px, white 70%, uppercase
- Speed: 36px, bold, white
- Unit: 14px, white 70%
- Distance: 12px, white 70%

### 3. Preview Thumbnail
```
┌──────┐
│      │
│ 📷   │
│      │
└──────┘
```
- Size: 80x80px
- Background: White 10% opacity
- Border: White 30% opacity, 2px
- Border radius: 12px
- Icon: 40px, white 50% (when empty)

### 4. Mode Selector
```
┌─────────────────────────────┐
│ VIDEO │ RADAR │ PHOTO      │
└─────────────────────────────┘
```
- Container: Black 50% opacity
- Border: White 20% opacity, 1px
- Border radius: 30px
- Padding: 12px horizontal, 8px vertical
- Selected: White 20% background
- Text: 14px, bold when selected
- Letter spacing: 1px

## Color Usage Guide

### Dashboard Colors
- **Background**: Gradient (teal → white)
- **Text**: Dark (#2C3E50)
- **Primary**: Teal (#1C9A9A)
- **Cards**: White with opacity
- **Shadows**: Black 5-10% opacity

### Camera Mode Colors
- **Background**: Black (camera)
- **Text**: White
- **Overlays**: Black/White with opacity
- **Borders**: White 20-30% opacity
- **Highlights**: White 20% opacity

## Spacing & Padding Standards

### Dashboard
- Screen margins: 20px
- Card spacing: 12px
- Section spacing: 20-30px
- Button padding: 18px vertical

### Camera Mode
- Safe area + padding: 20-50px
- Card padding: 16px
- Control spacing: 20-40px
- Element spacing: 8-12px

## Responsive Behavior

### Dashboard
- Speedometer: Fixed 280x280px (centered)
- Stats cards: Flex equal width
- Button: Full width minus margins
- All elements: Vertical scroll if needed

### Camera Mode
- Camera: Fill available space
- Vehicle card: Fixed position (responsive to safe area)
- Bottom controls: Fixed to bottom with safe area
- Mode selector: Centered horizontally

## Animation & Interaction

### Dashboard
- Speedometer: Animate progress ring on speed change
- Tabs: Fade transition between views
- Button: Scale slightly on press (0.98)
- Cards: Subtle elevation on hover (web)

### Camera Mode
- Mode selector: Smooth background slide
- Vehicle card: Fade in/out based on detection
- Close button: Scale on press
- Thumbnail: Update with fade transition

## Accessibility Notes
- All interactive elements: Min 44x44px touch target
- Text contrast: Meets WCAG AA standards
- Icons: Paired with text labels
- Status indicators: Color + icon/text
- Focus indicators: Clear visual feedback

