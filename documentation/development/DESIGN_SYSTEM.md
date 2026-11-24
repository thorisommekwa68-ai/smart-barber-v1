# Shared Design System

## Brand palette

- Primary: `#101820`
- Secondary: `#D4AF37`
- Background: `#F5F6F8`
- Surface: `#FFFFFF`
- Primary text: `#20252B`
- Muted text: `#777F88`

Application accents may be tuned for audience needs, but these core brand values must remain recognizable.

## Typography

Use a clean system or hosted sans-serif font. Initial prototypes use DM Sans and Manrope. Shared type roles should cover page titles, section headings, card headings, body text and captions.

## Spacing

Use a small spacing scale such as 4, 8, 12, 16, 24, 32 and 48 pixels. Components must use shared CSS variables instead of isolated hard-coded values.

## Components

- Buttons: primary, secondary, text and destructive variants.
- Forms: labels, inputs, selects, textareas, validation and helper text.
- Navigation: sidebar, top bar and mobile navigation patterns.
- Cards: consistent surface, border, radius and shadow behavior.
- Modals and drawers: accessible focus handling and close actions.
- Tables: responsive layouts, sorting states and empty states.
- Notifications: success, warning, error and informational variants.
- Status indicators: active, pending, approved, declined and cancelled states.

## Responsive layout

Shared layouts should support desktop, tablet and mobile widths. Navigation and dense tables require deliberate mobile behavior rather than horizontal overflow.

Implementation belongs in `packages/shared-ui` after the current prototypes are safely separated into CSS and JavaScript modules.

## Implemented application tokens

The initial visual implementation uses app-local public CSS layers:

- `apps/customer-app/public/styles/shared.css`
- `apps/customer-app/public/styles/customer.css`
- `apps/merchant-app/public/styles/shared.css`
- `apps/merchant-app/public/styles/merchant.css`
- `apps/deployment-manager/public/styles/shared.css`
- `apps/deployment-manager/public/styles/deployment.css`

The shared palette is also documented in `documentation/development/DESIGN_SYSTEM.md`. The application overrides deliberately keep their different interaction models: marketplace discovery for customers and dense operational surfaces for business and platform users.

## Visual research

Dribbble searches reviewed for broad direction:

- <https://dribbble.com/search/barber-booking-app>
- <https://dribbble.com/search/salon-appointment-app>
- <https://dribbble.com/search/appointment-dashboard>
- <https://dribbble.com/search/saas-admin-dashboard>
- <https://dribbble.com/search/crm-dashboard>
- <https://dribbble.com/search/salon-marketplace>

Automated review of Dribbble search pages was limited by the website response, so no individual artwork was copied or downloaded. The implementation instead uses general product-design principles commonly found across premium booking and SaaS interfaces: strong page hierarchy, restrained accent colour, visible state, compact mobile navigation, generous card rhythm, clear scan paths, and purposeful data density.
