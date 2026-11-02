import Foundation

enum DiscordPresenceFactory {
    @MainActor
    static func make(
        session: PlaybackSession,
        snapshot: PlaybackSnapshot,
        preferences: Preferences,
        artworkURL: URL?,
        now: Date
    ) -> DiscordPresence {
        let album = preferences.showAlbum ? (session.track.album ?? "") : ""
        let lineOne = template(
            format: preferences.discordLineOne,
            custom: preferences.discordCustomLineOne,
            track: session.track,
            album: album
        )
        let lineTwo = template(
            format: preferences.discordLineTwo,
            custom: preferences.discordCustomLineTwo,
            track: session.track,
            album: album
        )
        let isPaused = snapshot.state == .paused
        let playbackState = isPaused ? "Paused" : "Playing"
        let rawPosition = snapshot.position.isFinite ? max(0, snapshot.position) : 0
        let position = session.track.supportsFiniteProgress ? min(rawPosition, session.track.duration) : rawPosition
        let stateTemplate = snapshot.state == .paused ? preferences.discordPausedText : lineTwo
        let render: (String) -> String = { value in
            DiscordTemplate.render(
                value, title: session.track.title, artist: session.track.artist,
                album: album, platform: session.track.platform,
                playbackState: playbackState, position: position,
                duration: session.track.duration
            )
        }
        let showsDuration = session.track.supportsFiniteProgress && preferences.discordTimerStyle != .hidden
        let supportsTimer = snapshot.state == .playing && showsDuration
        let startedAt =
            supportsTimer && (preferences.discordTimerStyle == .elapsed || preferences.discordTimerStyle == .progress)
            ? now.addingTimeInterval(-position) : nil
        let endsAt =
            supportsTimer && (preferences.discordTimerStyle == .remaining || preferences.discordTimerStyle == .progress)
            ? now.addingTimeInterval(session.track.duration - position) : nil
        var state = render(stateTemplate)
        if showsDuration, !stateTemplate.contains("{duration}"), (isPaused || !lineOne.contains("{duration}")) {
            let timing =
                isPaused && !stateTemplate.contains("{position}")
                ? render("{position} / {duration}") : render("{duration}")
            state = [state, timing].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let smallImageTemplate =
            isPaused && preferences.discordSmallImageText == "Playing on {platform}"
            ? "Paused on {platform}" : preferences.discordSmallImageText

        return DiscordPresence(
            title: render(lineOne), state: state,
            startedAt: startedAt, endsAt: endsAt,
            appleMusicURL: preferences.showLink ? session.track.appleMusicURL : nil,
            artworkURL: artworkURL, buttonLabel: preferences.discordButtonLabel,
            platform: session.track.platform, smallImage: preferences.discordSmallImage,
            largeImage: preferences.discordLargeImage, activityType: preferences.discordActivityType,
            activityName: render(preferences.discordActivityName),
            largeImageText: render(preferences.discordLargeImageText),
            smallImageText: render(smallImageTemplate)
        )
    }

    private static func template(
        format: DiscordLineFormat,
        custom: String,
        track: TrackMetadata,
        album: String
    ) -> String {
        format == .custom
            ? custom
            : format.value(title: track.title, artist: track.artist, album: album)
    }
}
