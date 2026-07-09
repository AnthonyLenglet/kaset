# ADR 0021: Shared `MediaCard` for thumbnail-over-title shelves and grids

**Date:** 2026-07-09
**Status:** Proposed

## Context

Adding a hover "play" button to playlist/album/single thumbnails
(the quick-play feature) surfaced how many near-identical card views the app
carries. A "media card" (a square (or circular) thumbnail with a title, shown in
a horizontal shelf or a grid) is re-implemented **21 times** across the codebase.

An inventory grouped them into three visual clusters:

1. **Square music cards** (~13): album / playlist / podcast-show / uploads /
   library cards. Thumbnail + title + optional subtitle, corner radius 8.
2. **Circular artist cards** (3): with `.circle` clipping and centered text
   (`ArtistDetailView.artistCard`, `.relatedArtistCard`, `LibraryView.artistCard`).
3. **16:9 video / episode cards** (5): YouTube videos, podcast episodes, live
   streams. Materially different (aspect ratio, duration / LIVE badges,
   watched-progress bars).

The quick-play feature alone forced three parallel edits
(`HomeSectionItemCard`, a cloned `ItemCardContent`, and per-`func` artist
cards), plus a `PlayableArtistCard` overlay wrapper, because no existing card
could be reused.

### Root cause

The most-used card, `HomeSectionItemCard`, **bakes in a `Button`**. It cannot
be placed inside a `NavigationLink`. The app has two navigation patterns:

- **Pattern 1** — the view owns a `NavigationPath`; the card is a
  `Button { path.append(…) }` (`HomeView`, `ExploreView`, `ChartsView`,
  `NewReleasesView`, `MoodsAndGenresView`, `LibraryView`, `PodcastsView`).
- **Pattern 2** — the view is pushed onto a parent stack and has no path; the
  card is plain content wrapped by `NavigationLink(value:)`
  (`MoodCategoryDetailView`, `ArtistDetailView`, `ArtistDiscographyView`, all
  YouTube grids).

Because `HomeSectionItemCard` is Button-first, `MoodCategoryDetailView` had to
clone a Button-less twin (`ItemCardContent`) for Pattern 2, and
`ArtistDetailView` grew its own `func`-based cards. The `PlayableArtistCard`
wrapper added during quick-play is, accidentally, the correct shape: **content
only, navigation supplied from outside.**

## Decision

Introduce one **tap-agnostic, config-driven** `MediaCard` for clusters 1 and 2,
and migrate those call sites to it. The 16:9 video/episode cluster
and the feature-rich `HomeSectionItemCard` are **out of scope** (see below).

### `MediaCard` API

`MediaCard` renders content only. The call site supplies navigation by
wrapping it (a `Button` for Pattern 1, a `NavigationLink` for Pattern 2).
Hover chrome (scale + shadow, and the play button when `playAction` is non-nil)
is owned internally, folding in what `PlayableArtistCard` did.

```swift
struct MediaCard: View {
    enum ThumbnailShape { case square, circle }
    enum PlaceholderStyle { case material, titleGradient }

    let title: String
    var subtitle: String? = nil
    let thumbnailURL: URL?
    var shape: ThumbnailShape = .square
    var width: CGFloat = 160
    var placeholderSystemImage: String = "music.note"
    var placeholderStyle: PlaceholderStyle = .material
    /// When non-nil, a play button appears over the thumbnail on hover and
    /// invokes this instead of the surrounding navigation.
    var playAction: (() -> Void)? = nil
}
```

Deliberately **not** an enum-driven `MediaCard(item: SomeEnum)`: over half the
call sites hold raw `Album` / `Playlist` / `Artist` / `PodcastShow` values, not
a `HomeSectionItem`. Passing plain fields avoids forcing a universal wrapper
enum and keeps each call site readable. Overlays specific to one card
(like-heart, explicit badge, rank badge, video/episode badges, progress bars)
are intentionally _absent_ from the API — cards that need them stay on their
own component rather than growing `MediaCard` into a flag-driven
god-component.

### Real rewrites

**Artist album card** (`ArtistDetailView`) — before:

```swift
NavigationLink(value: self.playlistFromAlbum(album)) {
    PlayableArtistCard(playAction: self.quickPlayAction(for: album), thumbnailSize: 140) {
        self.albumCard(album)
    }
}
.buttonStyle(.plain)
```

after (the `albumCard(_:)` func and the `PlayableArtistCard` wrapper both
disappear):

```swift
NavigationLink(value: self.playlistFromAlbum(album)) {
    MediaCard(
        title: album.title,
        subtitle: album.year,
        thumbnailURL: album.thumbnailURL?.highQualityThumbnailURL,
        width: 140,
        placeholderSystemImage: "square.stack",
        placeholderStyle: .material,
        playAction: self.quickPlayAction(for: album)
    )
}
.buttonStyle(.plain)
```

**Library playlist card** (`LibraryView`, Pattern 1) — before:

```swift
Button {
    self.navigationPath.append(playlist)
} label: {
    VStack(alignment: .leading, spacing: 8) {
        CachedAsyncImage(url: playlist.thumbnailURL?.highQualityThumbnailURL) { … }
            .frame(width: libraryItemSize, height: libraryItemSize)
            .clipShape(.rect(cornerRadius: 8))
        Text(playlist.title) …
        Text(songCountText) …
    }
}
.buttonStyle(.plain)
```

after:

```swift
Button {
    self.navigationPath.append(playlist)
} label: {
    MediaCard(
        title: playlist.title,
        subtitle: self.songCountText(playlist),
        thumbnailURL: playlist.thumbnailURL?.highQualityThumbnailURL,
        width: libraryItemSize,
        placeholderSystemImage: "music.note.list"
    )
}
.buttonStyle(.plain)
```

The same `MediaCard` serves both navigation patterns because it owns no tap
handling.

### Migration scope (this slice)

Migrate and delete these renderers:

| Migrate                                                                   | From                                  |
| ------------------------------------------------------------------------- | ------------------------------------- |
| `ItemCardContent`                                                         | `MoodCategoryDetailView`              |
| `albumCard`, `playlistCard`, `artistCard`, inline playlist, `podcastCard` | `ArtistDetailView`                    |
| `relatedArtistCard`                                                       | `ArtistDetailView`                    |
| `albumCard`                                                               | `ArtistDiscographyView`               |
| `playlistCard`, `uploadedSongsCard`, `podcastCard`, `artistCard`          | `LibraryView`                         |
| `PodcastShowCard`                                                         | `PodcastsView`                        |
| `PlayableArtistCard`                                                      | folded into `MediaCard`, then removed |

Behavior is preserved 1:1: `playAction` is passed only where it exists today
(artist album/playlist, discography, mood-category real playlists). Cards that
navigate-only today stay navigate-only (no new play buttons in Library /
Podcasts in this slice).

### Explicitly out of scope

- **`HomeSectionItemCard`** — carries like-heart, explicit badge, chart-rank
  badge, and a wide video-song variant. Migrating it means either bloating
  `MediaCard` or composing overlays on top of it.
- **16:9 video / episode cards** (`VideoCard`, `VideoThumbnailView`,
  `YouTubePlaylistCard`, `ArtistDetailView.episodeCard`, `PodcastEpisodeCard`)
  — different aspect ratio and badge/progress chrome; a separate shared
  `VideoCard` is a distinct decision.
- **`FavoriteItemCard`** — drag-to-reorder affordance and a non-LiquidGlass
  play glyph.

## Consequences

- ~13 renderers collapse to one component plus thin call-site
  field mapping; the `ItemCardContent` and `PlayableArtistCard` clones and the
  per-`func` artist cards are deleted.
- The Button-vs-NavigationLink fork that caused the cloning is
  resolved structurally — a content-only card drops into either pattern.
- some plain cards that lacked hover scale/shadow today gain it
- (they already sit next to cards that have it). The play glyph and
  placeholder handling become consistent. Any card whose placeholder
  currently uses a title-hash gradient keeps it via `placeholderStyle: .titleGradient`.

## Alternatives considered

### One universal `MediaCard(item:)` enum + all overlays as flags

Rejected. Forces raw-value call sites into a wrapper enum they don't have, and
turns the component into a flag-driven god-view (`showLikeButton`, `isVideo`,
`rankBadge`, `progressBar`…) — replacing duplication with conditional
complexity. Conflicts with the project's "simplicity over type gymnastics"
stance.

### Make `HomeSectionItemCard` tap-agnostic and reuse it everywhere

Rejected for this slice. It carries song-specific overlays (like, explicit,
video variant) irrelevant to album/playlist/artist cards; every non-song site
would pay for machinery it never uses. Better to prove a lean `MediaCard`
first, then evaluate re-expressing `HomeSectionItemCard` _on top of_ it.
