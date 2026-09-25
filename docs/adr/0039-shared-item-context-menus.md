# ADR-0039: Shared context menus per item type

## Status

Accepted

## Context

Each page built its own right-click menu from single-entry helpers
(`FavoritesContextMenu`, `ShareContextMenu`, `LikeDislikeContextMenu`,
`AddToQueueContextMenu`, `AddToPlaylistContextMenu`, `StartRadioContextMenu`).
The same item type got different entries and orders depending on the page,
and several pages (Explore, Charts, New Releases, Moods & Genres, most Artist
shelves, podcast episodes) had no menu at all.

## Decision

`SharedViews/ItemContextMenus.swift` defines one menu per item type:
`SongContextMenu`, `AlbumContextMenu`, `PlaylistContextMenu`,
`ArtistContextMenu`, `PodcastShowContextMenu` and `EpisodeContextMenu`, plus
`HomeSectionItemContextMenu` and `SearchResultItemContextMenu` to dispatch on
the item enums. Pages call these instead of assembling entries.

The entries are the union of what any page offered for that type, in the order
most pages already used, with one exception: songs and episodes have no Play
entry, because tapping them already plays. Albums keep Play, since tapping an
album opens it. What legitimately differs by page is passed in:

- `navigate`: a `(any Hashable) -> Void` sink for "View…" and "Go to…"
  entries. Nil uses `NavigationLink(value:)`; hosts outside a
  `NavigationStack`, or menus hosted in `NSHostingMenu`, route the value
  themselves.
- `extras`: page-only entries appended last, such as Remove from Playlist,
  Remove from Queue, Delete Playlist, or Favorites reordering.
- `showsGoToArtist` / `showsViewPodcast`: turned off where the link would
  point at the page already open (an artist's top songs, a podcast's
  episodes).

## Consequences

- Adding or reordering an entry for a type is one change, and every page picks
  it up.
- Entries a type has on one page now appear on all pages, e.g. Add to Library
  for songs on Home and History, Share for podcast shows.
- A menu with needs not covered by `play`, `navigate` or `extras` should extend
  the shared type rather than go back to an inline menu.
- Out of scope: the AppKit queue side panel menu, the sidebar's pinned-item
  menu (reordering only), and YouTube (non-music) views.
