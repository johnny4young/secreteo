import AppKit
import XCTest

final class DictationUITests: SecreteoUITestCase {
    @MainActor
    func testClipboardBorrowRestoresRichPrivateContentAndKeepsTextInRecovery() throws {
        let name = "com.johnny4young.secreteo.dictation-test.\(UUID().uuidString)"
        let board = NSPasteboard(name: .init(name))
        defer { board.releaseGlobally() }
        let original = NSPasteboardItem()
        original.setString("Keep private original", forType: .string)
        original.setData(Data("<p>Keep private original</p>".utf8), forType: .html)
        original.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        XCTAssertTrue(board.writeObjects([original]))
        let generation = board.changeCount
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-clipboard"]
        app.launchEnvironment["SECRETEO_UI_TEST_DICTATION_PASTEBOARD"] = name
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let transcript = app.staticTexts["dictation-panel-transcript"]
        XCTAssertTrue(transcript.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: transcript).contains("No borres estas notas.")
        })
        // The production controller deliberately cancels audio shorter than
        // 0.75 s. Measure from the first caption, not an arbitrary launch wait.
        let firstCaption = ContinuousClock.now
        XCTAssertTrue(waitForUITestCondition(timeout: 2) {
            firstCaption.duration(to: .now) >= .milliseconds(800)
        })
        dictate.click()
        // The fixture borrows the named board with the production inserter but
        // never posts the paste, so delivery is refused into recovery and every
        // original representation, including the private marker, comes back.
        let title = app.descendants(matching: .any)["dictation-recovery-title"]
        XCTAssertTrue(title.waitForExistenceFast(timeout: 5))
        XCTAssertTrue(app.control(withIdentifier: "dictation-recovery-reason").exists)
        attachScreenshot(named: "pr-panel-recovery")
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            board.string(forType: .string) == "Keep private original"
        })
        XCTAssertEqual(board.pasteboardItems?.count, 1)
        XCTAssertEqual(board.data(forType: .html), Data("<p>Keep private original</p>".utf8))
        XCTAssertTrue(board.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
        XCTAssertNotEqual(board.changeCount, generation, "The clipboard was borrowed and restored, not skipped")
        let text = app.descendants(matching: .any)["dictation-recovery-text"]
        XCTAssertTrue(renderedText(of: text).contains("No borres estas notas."))
        let discard = app.buttons["dictation-recovery-discard"]
        XCTAssertTrue(discard.waitForStableFrame(timeout: 5))
        discard.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !discard.exists })
    }

    @MainActor
    func testDictationCaptureFailureIsVisibleAndCanBeDismissed() async throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-capture-failure"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let message = UITestLocale.environmentLocale == "es"
            ? "Se interrumpió la captura de audio. No se insertó nada. Vuelve a dictar."
            : "Audio capture was interrupted. Nothing was inserted. Try dictating again."

        for _ in 0..<2 {
            XCTAssertTrue(app.prepareForInteraction())
            let dictate = app.buttons["menu-bar-dictate"]
            XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
            dictate.click()
            let state = app.staticTexts["dictation-panel-state"]
            XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: state) == message })
            XCTAssertFalse(app.descendants(matching: .any)["dictation-panel-meter"].exists)
            let cancel = app.buttons["dictation-panel-cancel"]
            XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
            cancel.click()
            XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
        }
    }

    @MainActor
    func testDictationPanelCancelsAndRestartsWithoutGlobalInput() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments.append("-seed-dictation")
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationMouseButton":2}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }

        for _ in 0..<2 {
            XCTAssertTrue(app.prepareForInteraction())
            let dictate = app.buttons["menu-bar-dictate"]
            XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
            dictate.click()
            let transcript = app.staticTexts["dictation-panel-transcript"]
            guard transcript.waitForExistenceFast(timeout: 5) else {
                XCTFail("The running dictation must expose its transcript independently of the panel container.")
                return
            }
            XCTAssertTrue(waitForUITestCondition(timeout: 5) {
                renderedText(of: transcript).contains("No borres estas notas.")
            })
            for identifier in ["dictation-panel-state", "dictation-panel-target", "dictation-panel-meter"] {
                XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 1)
            }
            let cancel = app.buttons["dictation-panel-cancel"]
            XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
            cancel.click()
            XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
        }
    }

    @MainActor
    func testStreamingDictationKeepsClosedRowsThroughCancellationAndRestart() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-streaming"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        let expected = "No borres estas notas. Café C++. Final"
        for _ in 0..<2 {
            XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
            dictate.click()
            let transcript = app.staticTexts["dictation-panel-transcript"]
            XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: transcript) == expected })
            let cancel = app.buttons["dictation-panel-cancel"]
            XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
            cancel.click()
            XCTAssertTrue(waitForUITestCondition(timeout: 5) { !transcript.exists })
        }
    }

    @MainActor
    func testMicrophoneDenialRemainsRecoverableWithoutOpeningAudio() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-microphone-denied"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let state = app.staticTexts["dictation-panel-state"]
        let message = UITestLocale.environmentLocale == "es"
            ? "Permite el acceso al micrófono en Ajustes del Sistema y vuelve a intentar el dictado."
            : "Allow microphone access in System Settings, then try dictation again."
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: state) == message })
        XCTAssertFalse(app.descendants(matching: .any)["dictation-panel-meter"].exists)
        let cancel = app.buttons["dictation-panel-cancel"]
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
        cancel.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let transcript = app.staticTexts["dictation-panel-transcript"]
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: transcript).contains("No borres estas notas.")
        })
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
        cancel.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
    }

    @MainActor
    func testMissingMicrophoneAudioShowsFallbackAndAllowsRestart() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-microphone-no-audio"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let state = app.staticTexts["dictation-panel-state"]
        let message = UITestLocale.environmentLocale == "es"
            ? "No llegó audio del micrófono. Revisa el micrófono en los ajustes de Audio e inténtalo de nuevo."
            : "No microphone audio arrived. Check the microphone in Audio settings and try again."
        XCTAssertTrue(waitForUITestCondition(timeout: 10) { renderedText(of: state) == message })
        let notice = app.staticTexts["dictation-panel-microphone-notice"]
        XCTAssertTrue(notice.exists)
        XCTAssertFalse(app.staticTexts["dictation-panel-transcript"].exists)
        let cancel = app.buttons["dictation-panel-cancel"]
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
        cancel.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let transcript = app.staticTexts["dictation-panel-transcript"]
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: transcript).contains("No borres estas notas.")
        })
        XCTAssertTrue(notice.exists)
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
        cancel.click()
    }

    @MainActor
    func testPreparingDictationCanCancelWithoutAListeningClaim() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-preparation-held"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let state = app.staticTexts["dictation-panel-state"]
        let title = UITestLocale.environmentLocale == "es" ? "Preparando el dictado…" : "Preparing dictation…"
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: state) == title })
        XCTAssertFalse(app.descendants(matching: .any)["dictation-panel-meter"].exists)
        XCTAssertFalse(app.staticTexts["dictation-panel-transcript"].exists)
        let cancel = app.buttons["dictation-panel-cancel"]
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
        cancel.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
    }

    @MainActor
    func testLoadingModelLooksDifferentFromDictating() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-model-loading"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let state = app.staticTexts["dictation-panel-state"]
        let title = UITestLocale.environmentLocale == "es" ? "Cargando el modelo de voz…" : "Loading speech model…"
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: state) == title })
        XCTAssertTrue(app.descendants(matching: .any)["dictation-panel-loading"].exists)
        let hint = UITestLocale.environmentLocale == "es"
            ? "Sigue hablando. Tus palabras aparecen cuando el modelo esté listo."
            : "Keep talking. Your words appear once the model is ready."
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: app.staticTexts["dictation-panel-hint"]) == hint
        })
        XCTAssertFalse(app.staticTexts["dictation-panel-transcript"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["dictation-panel-meter"].exists, "audio is still captured")
        let cancel = app.buttons["dictation-panel-cancel"]
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
        cancel.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
    }

    @MainActor
    func testCompactIndicatorShowsOnlyTheLevelAndTime() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-model-loading"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationCompactIndicator":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let compact = app.descendants(matching: .any)["dictation-panel-compact"]
        XCTAssertTrue(compact.waitForExistenceFast(timeout: 5))
        let elapsed = app.staticTexts["dictation-panel-elapsed"]
        XCTAssertTrue(waitForUITestCondition(timeout: 5) {
            renderedText(of: elapsed).range(of: #"^\d+:\d{2}$"#, options: .regularExpression) != nil
        }, "the elapsed time reads as m:ss")
        XCTAssertTrue(app.descendants(matching: .any)["dictation-panel-meter"].exists)
        XCTAssertFalse(app.buttons["dictation-panel-cancel"].exists, "no buttons in the compact indicator")
        XCTAssertFalse(app.staticTexts["dictation-panel-state"].exists, "no live text or title")
        XCTAssertLessThan(app.dialogs["dictation-panel"].frame.width, 200)
    }

    @MainActor
    func testCompactIndicatorCanBeDraggedWhileDictating() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-model-loading"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationCompactIndicator":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let panel = app.dialogs["dictation-panel"]
        XCTAssertTrue(panel.waitForExistenceFast(timeout: 5))
        let before = panel.frame
        let grab = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        grab.press(forDuration: 0.2, thenDragTo: grab.withOffset(CGVector(dx: -160, dy: -120)))
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { panel.frame.origin != before.origin },
                      "the floating indicator moves where the user drags it")
        XCTAssertEqual(panel.frame.size, before.size)
    }

    @MainActor
    func testCompactIndicatorOpensTheFullPanelForAFailure() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-capture-failure"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] =
            #"{"globalDictationEnabled":true,"dictationCompactIndicator":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        let cancel = app.buttons["dictation-panel-cancel"]
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5), "a failure shows the full panel and its controls")
        XCTAssertGreaterThan(app.dialogs["dictation-panel"].frame.width, 500, "the panel grows to fit the message")
    }

    @MainActor
    func testUndeliveredTextCanBeCopiedAndExplicitlyRetried() throws {
        let name = "com.johnny4young.secreteo.dictation-test." + UUID().uuidString
        let board = NSPasteboard(name: .init(name))
        defer { board.releaseGlobally() }
        board.setString("Original recovery clipboard", forType: .string)
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-recovery"]
        if UITestLocale.environmentLocale == "en" { app.launchArguments.append("-seed-dictation-english") }
        app.launchEnvironment["SECRETEO_UI_TEST_DICTATION_PASTEBOARD"] = name
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        enterDestinationRecovery(app)
        let text = app.descendants(matching: .any)["dictation-recovery-text"]
        XCTAssertTrue(renderedText(of: text).contains(recoveryFixtureText))
        let status = app.staticTexts["dictation-recovery-copy-status"]
        let initial = renderedText(of: status)
        for identifier in ["dictation-recovery-copy", "dictation-recovery-reinsert", "dictation-recovery-discard"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForStableFrame(timeout: 5))
            XCTAssertFalse(button.label.isEmpty)
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1)
            XCTAssertTrue(app.dialogs["dictation-panel"].frame.contains(button.frame),
                          "Long destination names must not push recovery actions outside the panel")
        }
        app.buttons["dictation-recovery-copy"].click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: status) != initial })
        XCTAssertEqual(board.string(forType: .string), "Original recovery clipboard")
        XCTAssertTrue(text.exists, "A failed copy must retain the output")
        app.buttons["dictation-recovery-copy"].click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { board.string(forType: .string) == recoveryFixtureText })
        XCTAssertTrue(text.exists, "Copy does not discard the user's recovery option")
        app.buttons["dictation-recovery-reinsert"].click()
        XCTAssertTrue(app.staticTexts["dictation-panel-delivery-status"].waitForExistenceFast(timeout: 5))
        XCTAssertFalse(text.exists)
    }

    @MainActor
    func testUndeliveredTextSurvivesAnotherTriggerUntilDiscarded() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-recovery"]
        if UITestLocale.environmentLocale == "en" { app.launchArguments.append("-seed-dictation-english") }
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        enterDestinationRecovery(app)
        let text = app.descendants(matching: .any)["dictation-recovery-text"]
        let original = renderedText(of: text)
        let originalFrame = app.dialogs["dictation-panel"].frame
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        guard !originalFrame.intersects(dictate.frame) else {
            return XCTFail("The menu fixture must not place Dictate beneath the recovery panel")
        }
        dictate.click()
        XCTAssertTrue(app.buttons["dictation-recovery-discard"].waitForStableFrame(timeout: 5))
        XCTAssertEqual(renderedText(of: text), original)
        XCTAssertEqual(app.dialogs["dictation-panel"].frame, originalFrame,
                       "Revealing retained text must not move a self-sizing panel")
        app.activate()
        let discard = app.buttons["dictation-recovery-discard"]
        guard discard.isHittable else {
            return XCTFail("Activating the disposable menu window must not occlude recovery")
        }
        discard.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !app.dialogs["dictation-panel"].exists },
                      "Discard must close the whole panel before another global trigger")
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        let cancel = app.buttons["dictation-panel-cancel"]
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
        cancel.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
    }

    @MainActor
    func testDeliveredDictationDistinguishesDispatchFromVerification() throws {
        for verified in [false, true] {
            let name = "com.johnny4young.secreteo.dictation-test." + UUID().uuidString
            let board = NSPasteboard(name: .init(name))
            defer { board.releaseGlobally() }
            board.setString("Original delivery clipboard", forType: .string)
            let app = try XCUIApplication.secreteo(showMenuBarContent: true)
            app.launchArguments += ["-seed-dictation", "-seed-dictation-delivery"]
            app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
            app.launchEnvironment["SECRETEO_UI_TEST_DICTATION_PASTEBOARD"] = name
            if UITestLocale.environmentLocale == "en" { app.launchArguments.append("-seed-dictation-english") }
            if verified { app.launchArguments.append("-seed-dictation-verified") }
            app.launchSecreteo()
            defer { finishUITestApplication(app) }
            enterDestinationDelivery(app)
            // The verified confirmation closes after 1.6 s, so one tree read sees all of it.
            let texts = renderedTexts(in: app)
            let status = app.staticTexts["dictation-panel-delivery-status"]
            let title = texts["dictation-panel-delivery-status"] ?? ""
            let detail = texts["dictation-panel-delivery-detail"]
            XCTAssertNotNil(detail)
            XCTAssertNil(texts["dictation-recovery-reinsert"],
                         "An unacknowledged event is not an automatically retryable refusal")
            if verified {
                XCTAssertTrue(title.contains("inserted") || title.contains("insertadas"), title)
                XCTAssertTrue(["Nothing was saved in Secreteo.", "No se guardó nada en Secreteo."]
                    .contains(detail ?? ""), detail ?? "")
                XCTAssertNil(texts["dictation-unverified-copy"])
                XCTAssertTrue(waitForUITestCondition(timeout: 5) { !status.exists })
            } else {
                XCTAssertTrue(["Sent — insertion not verified", "Enviado — inserción sin verificar"]
                    .contains(title), title)
                assertUnverifiedRecovery(app, board: board)
            }
        }
    }

    @MainActor
    func testUnverifiedNoticeClosesWithItsCloseButton() throws {
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-delivery"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        enterDestinationDelivery(app)
        let close = app.buttons["dictation-unverified-close"]
        XCTAssertTrue(close.waitForStableFrame(timeout: 5))
        close.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !close.exists }, "× closes the notice at once")
        XCTAssertFalse(app.staticTexts["dictation-unverified-text"].exists)
    }

    @MainActor
    func testSilentDictationIsOfferedToCopyInsteadOfPasted() throws {
        let name = "com.johnny4young.secreteo.dictation-test." + UUID().uuidString
        let board = NSPasteboard(name: .init(name))
        defer { board.releaseGlobally() }
        board.setString("Original delivery clipboard", forType: .string)
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-delivery", "-seed-dictation-no-speech"]
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchEnvironment["SECRETEO_UI_TEST_DICTATION_PASTEBOARD"] = name
        if UITestLocale.environmentLocale == "en" { app.launchArguments.append("-seed-dictation-english") }
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        enterDestinationDelivery(app)
        let status = app.staticTexts["dictation-panel-delivery-status"]
        XCTAssertTrue(["No speech detected — nothing was inserted", "No se detectó voz: no se insertó nada"]
            .contains(renderedText(of: status)), renderedText(of: status))
        XCTAssertEqual(renderedText(of: app.staticTexts["dictation-no-speech-text"]), recoveryFixtureText)
        XCTAssertFalse(app.buttons["dictation-recovery-reinsert"].exists, "Silence is offered, never re-sent")
        let copy = app.buttons["dictation-no-speech-copy"]
        XCTAssertTrue(copy.waitForStableFrame(timeout: 5))
        copy.click()
        XCTAssertEqual(board.string(forType: .string), "Original delivery clipboard", "The fixture's first Copy fails")
        copy.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { board.string(forType: .string) == recoveryFixtureText })
        XCTAssertTrue(app.control(withIdentifier: "dictation-no-speech-copy-status").waitForExistenceFast(timeout: 5))
        let discard = app.buttons["dictation-no-speech-discard"]
        XCTAssertTrue(discard.waitForStableFrame(timeout: 5))
        discard.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !app.dialogs["dictation-panel"].exists })
    }

    @MainActor
    func testDictationSourceEOFBeforeStopIsVisibleAndCanRestart() throws {
        let english = UITestLocale.environmentLocale == "en"
        let app = try XCUIApplication.secreteo(showMenuBarContent: true)
        app.launchArguments += ["-seed-dictation", "-seed-dictation-source-eof"]
        if english { app.launchArguments.append("-seed-dictation-english") }
        app.launchEnvironment["SECRETEO_UI_TEST_DEFAULTS"] = #"{"globalDictationEnabled":true}"#
        app.launchSecreteo()
        defer { finishUITestApplication(app) }
        let expectedText = english ? "Don't delete these notes." : "No borres estas notas."
        let expectedFailure = english
            ? "Audio capture was interrupted. Nothing was inserted. Try dictating again."
            : "Se interrumpió la captura de audio. No se insertó nada. Vuelve a dictar."

        for attempt in 0..<2 {
            XCTAssertTrue(app.prepareForInteraction())
            let dictate = app.buttons["menu-bar-dictate"]
            XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
            dictate.click()
            let state = app.staticTexts["dictation-panel-state"]
            let expectedState = attempt == 0 ? expectedFailure : (english ? "Dictating" : "Dictando")
            XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: state) == expectedState })
            if attempt == 0 {
                XCTAssertFalse(app.descendants(matching: .any)["dictation-panel-meter"].exists)
            } else {
                let transcript = app.staticTexts["dictation-panel-transcript"]
                XCTAssertTrue(waitForUITestCondition(timeout: 5) {
                    renderedText(of: transcript).contains(expectedText)
                })
            }
            let cancel = app.buttons["dictation-panel-cancel"]
            XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
            cancel.click()
            XCTAssertTrue(waitForUITestCondition(timeout: 5) { !cancel.exists })
        }
    }

}

private extension DictationUITests {
    var recoveryFixtureText: String {
        UITestLocale.environmentLocale == "en" ? "Don't delete these notes." : "No borres estas notas."
    }

    @MainActor
    func enterDestinationRecovery(_ app: XCUIApplication) {
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-recovery-title"].waitForExistenceFast(timeout: 5))
    }

    @MainActor
    func enterDestinationDelivery(_ app: XCUIApplication) {
        XCTAssertTrue(app.prepareForInteraction())
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertTrue(dictate.waitForStableFrame(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-transcript"].waitForExistenceFast(timeout: 5))
        dictate.click()
        XCTAssertTrue(app.staticTexts["dictation-panel-delivery-status"].waitForExistenceFast(timeout: 5))
    }

    @MainActor
    func assertUnverifiedRecovery(_ app: XCUIApplication, board: NSPasteboard) {
        let text = app.staticTexts["dictation-unverified-text"]
        XCTAssertEqual(renderedText(of: text), recoveryFixtureText)
        let status = app.staticTexts["dictation-unverified-copy-status"]
        let originalStatus = renderedText(of: status)
        let panel = app.dialogs["dictation-panel"]
        let originalFrame = panel.frame
        for identifier in ["dictation-unverified-copy", "dictation-unverified-discard", "dictation-unverified-close"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForStableFrame(timeout: 5))
            XCTAssertFalse(button.label.isEmpty)
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1)
            XCTAssertTrue(originalFrame.contains(button.frame))
        }
        let copy = app.buttons["dictation-unverified-copy"]
        copy.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { renderedText(of: status) != originalStatus })
        XCTAssertEqual(board.string(forType: .string), "Original delivery clipboard")
        XCTAssertTrue(text.exists, "Failed Copy must preserve output")
        copy.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { board.string(forType: .string) == recoveryFixtureText })
        let dictate = app.buttons["menu-bar-dictate"]
        XCTAssertFalse(originalFrame.intersects(dictate.frame))
        dictate.click()
        // An unverified notice is non-modal: the next dictation starts and
        // replaces it, and the previous output is not sent again.
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !text.exists }, "Another trigger starts a new capture")
        let cancel = app.buttons["dictation-panel-cancel"]
        XCTAssertTrue(cancel.waitForStableFrame(timeout: 5))
        XCTAssertEqual(board.string(forType: .string), recoveryFixtureText, "A new capture never re-sends output")
        app.activate()
        cancel.click()
        XCTAssertTrue(waitForUITestCondition(timeout: 5) { !panel.exists }, "Cancel must exit in one action")
    }

}
