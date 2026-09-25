import SwiftUI

// MARK: - ContextMenuNavigate

/// Destination sink for "View…" and "Go to…" entries. Hosts inside a
/// `NavigationStack` can pass nil to use `NavigationLink`; hosts outside one
/// route the value themselves.
typealias ContextMenuNavigate = (any Hashable) -> Void

// MARK: - ContextMenuNavigationButton

private struct ContextMenuNavigationButton<Value: Hashable>: View {
    let value: Value
    let title: String
    let systemImage: String
    let navigate: ContextMenuNavigate?

    var body: some View {
        if let navigate {
            Button {
                navigate(self.value)
            } label: {
                Label(self.title, systemImage: self.systemImage)
            }
        } else {
            NavigationLink(value: self.value) {
                Label(self.title, systemImage: self.systemImage)
            }
        }
    }
}

extension Album {
    /// Albums open in the playlist detail view.
    func detailPlaylist(fallbackThumbnailURL: URL? = nil) -> Playlist {
        Playlist(
            id: self.id,
            title: self.title,
            description: nil,
            thumbnailURL: self.thumbnailURL ?? fallbackThumbnailURL,
            trackCount: self.trackCount,
            author: self.artistsDisplay.isEmpty
                ? nil
                : Artist.inline(name: self.artistsDisplay, namespace: "album-artist"),
            libraryTargetId: self.libraryTargetId
        )
    }
}

// MARK: - SongContextMenu

/// Context menu entries for a song. There is no Play entry: tapping a song
/// already plays it. `extras` are appended last and should start with their
/// own `Divider`.
struct SongContextMenu<Extras: View>: View {
    let song: Song
    let client: (any YTMusicClientProtocol)?
    var navigate: ContextMenuNavigate?
    @ViewBuilder let extras: () -> Extras

    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(SongLikeStatusManager.self) private var likeStatusManager
    @Environment(AuthService.self) private var authService

    var body: some View {
        if self.authService.hasPersonalAccount {
            FavoritesContextMenu.menuItem(for: self.song, manager: self.favoritesManager)

            LikeDislikeContextMenu(song: self.song, likeStatusManager: self.likeStatusManager)

            Divider()
        }

        StartRadioContextMenu.menuItem(for: self.song, playerService: self.playerService)

        if self.authService.hasPersonalAccount {
            Button {
                SongActionsHelper.addToLibrary(self.song, playerService: self.playerService)
            } label: {
                Label(String(localized: "Add to Library"), systemImage: "plus.circle")
            }
        }

        if let client {
            AddToPlaylistContextMenu(song: self.song, client: client)
        }

        Divider()

        ShareContextMenu.menuItem(for: self.song)

        Divider()

        AddToQueueContextMenu(song: self.song, playerService: self.playerService)

        self.goToItems

        self.extras()
    }

    @ViewBuilder
    private var goToItems: some View {
        let artist = self.song.artists.first { $0.hasNavigableId }
        let album = self.song.album.flatMap { $0.hasNavigableId ? $0 : nil }

        if artist != nil || album != nil {
            Divider()
        }

        if let artist {
            ContextMenuNavigationButton(
                value: artist,
                title: String(localized: "Go to Artist"),
                systemImage: "person",
                navigate: self.navigate
            )
        }

        if let album {
            ContextMenuNavigationButton(
                value: album.detailPlaylist(fallbackThumbnailURL: self.song.thumbnailURL),
                title: String(localized: "Go to Album"),
                systemImage: "square.stack",
                navigate: self.navigate
            )
        }
    }
}

extension SongContextMenu where Extras == EmptyView {
    init(
        song: Song,
        client: (any YTMusicClientProtocol)?,
        navigate: ContextMenuNavigate? = nil
    ) {
        self.init(song: song, client: client, navigate: navigate) {
            EmptyView()
        }
    }
}

// MARK: - AlbumContextMenu

struct AlbumContextMenu: View {
    let album: Album
    let client: any YTMusicClientProtocol
    var isAudiobook = false
    var navigate: ContextMenuNavigate?

    @Environment(PlayerService.self) private var playerService
    @Environment(FavoritesManager.self) private var favoritesManager

    var body: some View {
        ContextMenuNavigationButton(
            value: self.album.detailPlaylist(),
            title: self.isAudiobook ? String(localized: "View Audiobook") : String(localized: "View Album"),
            systemImage: self.isAudiobook ? "books.vertical" : "square.stack",
            navigate: self.navigate
        )

        Divider()

        Button {
            SongActionsHelper.playAlbum(self.album, client: self.client, playerService: self.playerService)
        } label: {
            Label(String(localized: "Play"), systemImage: "play.fill")
        }

        Button {
            SongActionsHelper.addAlbumToQueueNext(self.album, client: self.client, playerService: self.playerService)
        } label: {
            Label(String(localized: "Play Next"), systemImage: "text.insert")
        }

        Button {
            SongActionsHelper.addAlbumToQueueLast(self.album, client: self.client, playerService: self.playerService)
        } label: {
            Label(String(localized: "Add to Queue"), systemImage: "text.append")
        }

        Divider()

        FavoritesContextMenu.menuItem(for: self.album, manager: self.favoritesManager)

        ShareContextMenu.menuItem(for: self.album)
    }
}

// MARK: - PlaylistContextMenu

/// `extras` are appended last and should start with their own `Divider`.
struct PlaylistContextMenu<Extras: View>: View {
    let playlist: Playlist
    let client: any YTMusicClientProtocol
    var showsAddToLibrary = true
    var navigate: ContextMenuNavigate?
    @ViewBuilder let extras: () -> Extras

    @Environment(FavoritesManager.self) private var favoritesManager
    @Environment(AuthService.self) private var authService
    @Environment(\.libraryViewModel) private var libraryViewModel: LibraryViewModel?

    var body: some View {
        ContextMenuNavigationButton(
            value: self.playlist,
            title: String(localized: "View Playlist"),
            systemImage: "music.note.list",
            navigate: self.navigate
        )

        Divider()

        if self.showsAddToLibrary, self.authService.hasPersonalAccount {
            Button {
                Task {
                    try? await SongActionsHelper.addPlaylistToLibrary(
                        self.playlist,
                        client: self.client,
                        libraryViewModel: self.libraryViewModel
                    )
                }
            } label: {
                Label(String(localized: "Add to Library"), systemImage: "plus.circle")
            }
        }

        FavoritesContextMenu.menuItem(for: self.playlist, manager: self.favoritesManager)

        ShareContextMenu.menuItem(for: self.playlist)

        self.extras()
    }
}

extension PlaylistContextMenu where Extras == EmptyView {
    init(
        playlist: Playlist,
        client: any YTMusicClientProtocol,
        showsAddToLibrary: Bool = true,
        navigate: ContextMenuNavigate? = nil
    ) {
        self.init(playlist: playlist, client: client, showsAddToLibrary: showsAddToLibrary, navigate: navigate) {
            EmptyView()
        }
    }
}

// MARK: - ArtistContextMenu

struct ArtistContextMenu: View {
    let artist: Artist
    var navigate: ContextMenuNavigate?

    @Environment(FavoritesManager.self) private var favoritesManager

    var body: some View {
        let isProfile = self.artist.profileKind == .profile
        ContextMenuNavigationButton(
            value: self.artist,
            title: isProfile ? String(localized: "View Profile") : String(localized: "View Artist"),
            systemImage: isProfile ? "person.crop.circle" : "person",
            navigate: self.navigate
        )

        Divider()

        FavoritesContextMenu.menuItem(for: self.artist, manager: self.favoritesManager)

        ShareContextMenu.menuItem(for: self.artist)
    }
}

// MARK: - PodcastShowContextMenu

struct PodcastShowContextMenu: View {
    let show: PodcastShow
    var navigate: ContextMenuNavigate?

    @Environment(FavoritesManager.self) private var favoritesManager

    var body: some View {
        ContextMenuNavigationButton(
            value: self.show,
            title: String(localized: "View Podcast"),
            systemImage: "mic.fill",
            navigate: self.navigate
        )

        Divider()

        FavoritesContextMenu.menuItem(for: self.show, manager: self.favoritesManager)

        ShareContextMenu.menuItem(for: self.show)
    }
}

// MARK: - EpisodeContextMenu

struct EpisodeContextMenu: View {
    let episode: PodcastEpisode
    var navigate: ContextMenuNavigate?

    @Environment(PlayerService.self) private var playerService

    var body: some View {
        let song = self.episode.playbackSong
        AddToQueueContextMenu(song: song, playerService: self.playerService)

        Divider()

        ShareContextMenu.menuItem(for: song)

        if let showBrowseId = self.episode.showBrowseId, let showTitle = self.episode.showTitle {
            Divider()

            ContextMenuNavigationButton(
                value: PodcastShow(
                    id: showBrowseId,
                    title: showTitle,
                    author: nil,
                    description: nil,
                    thumbnailURL: self.episode.thumbnailURL,
                    episodeCount: nil
                ),
                title: String(localized: "View Podcast"),
                systemImage: "mic.fill",
                navigate: self.navigate
            )
        }
    }
}

// MARK: - HomeSectionItemContextMenu

struct HomeSectionItemContextMenu: View {
    let item: HomeSectionItem
    let client: any YTMusicClientProtocol
    var navigate: ContextMenuNavigate?

    var body: some View {
        switch self.item {
        case let .song(song):
            SongContextMenu(song: song, client: self.client, navigate: self.navigate)
        case let .album(album):
            AlbumContextMenu(album: album, client: self.client, navigate: self.navigate)
        case let .playlist(playlist):
            // Mood and genre tiles arrive as playlists but open a category page.
            if playlist.resolvedMoodCategoryEndpoint == nil {
                PlaylistContextMenu(playlist: playlist, client: self.client, navigate: self.navigate)
            }
        case let .artist(artist):
            ArtistContextMenu(artist: artist, navigate: self.navigate)
        }
    }
}

// MARK: - SearchResultItemContextMenu

struct SearchResultItemContextMenu: View {
    let item: SearchResultItem
    let client: any YTMusicClientProtocol
    var navigate: ContextMenuNavigate?

    var body: some View {
        switch self.item {
        case let .song(song), let .video(song):
            SongContextMenu(song: song, client: self.client, navigate: self.navigate)
        case let .album(album):
            AlbumContextMenu(album: album, client: self.client, navigate: self.navigate)
        case let .audiobook(audiobook):
            AlbumContextMenu(album: audiobook, client: self.client, isAudiobook: true, navigate: self.navigate)
        case let .artist(artist), let .profile(artist):
            ArtistContextMenu(artist: artist, navigate: self.navigate)
        case let .playlist(playlist):
            PlaylistContextMenu(playlist: playlist, client: self.client, navigate: self.navigate)
        case let .podcastShow(show):
            PodcastShowContextMenu(show: show, navigate: self.navigate)
        case let .podcastEpisode(episode):
            EpisodeContextMenu(episode: episode, navigate: self.navigate)
        }
    }
}
