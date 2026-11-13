# Desktop widgets

Widgets need macOS 14 or later. To add one, right-click the desktop, choose **Edit Widgets**, and find **Claude Usage**.

| Widget | Sizes | Shows |
|---|---|---|
| Session Usage | Small | One large number for a profile, its track, and the weekly limit as a thin line |
| Usage Overview | Medium, large, extra large | Every profile you have selected for display |
| Active Profile | Medium | A headline number with a full-width track per limit and the time to reset |
| Usage Rings | Small, medium | Session and week as concentric rings, for one profile or up to four |
| Usage Dial | Small | One limit on a dial |
| Next Reset | Small | The time until the limits reset |

## Reading them

Each track or ring stands for the time window: five cells for the 5-hour session, seven for the week. The colored part is how much you have used. The thin marker shows how far through the window you are now. Color behind the marker means you have room; color past it means you will reach the limit before the reset.

A profile that has stopped updating turns grey and shows how old its reading is.

## Choosing a profile

Right-click a widget and choose **Edit Widget** to pick a profile. Left empty, the widget follows whichever profile is active in the app. Usage Overview has no picker: it shows the profiles selected under **Manage Profiles**.

The app only refreshes profiles it is displaying, so a widget pinned to a profile that is neither active nor shown in the menu bar will usually be grey.

## If a widget shows nothing

Open the app once so it can publish its data, and make sure it is running. The widgets read what the app last wrote; they never contact Claude themselves.
