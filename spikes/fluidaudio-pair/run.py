#!/usr/bin/env python3
"""Runs the same clips through two FluidAudio builds, alternating, in a scratch store. Run from this folder."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
ENGLISH = [
    "Please send the quarterly report to Ana before Friday at three thirty in the afternoon.",
    "We shipped version two point four of the app, and the crash rate dropped by twelve percent.",
    "I don't think we should merge this pull request until the tests pass on every machine.",
    "Remind me to call the dentist tomorrow morning, and then book two tickets to Chicago.",
    "Yes, that works for me.",
    "The meeting moved to next Tuesday. Nobody on the team could join today, so we will review the budget then. "
    "Please bring the updated numbers.",
]
# Escaped so the source stays ASCII English prose.
SPANISH = [
    "Por favor envía el informe trimestral a Ana antes del viernes a las tres y media de la tarde.",
    "Publicamos la versión dos punto cuatro de la aplicación y los errores bajaron un doce por ciento.",
    "No creo que debamos hacer el merge hasta que las pruebas pasen en todas las máquinas.",
    "Recuérdame llamar al dentista mañana por la mañana y luego comprar dos boletos para Bogotá.",
    "Sí, eso me funciona.",
    "La reunión pasó al próximo martes. Nadie del equipo pudo conectarse hoy, así que revisaremos el presupuesto "
    "entonces. Por favor trae los números actualizados.",
]
VOICES = {"en": ["Eddy (English (US))", "Flo (English (US))"], "es": ["Eddy (Spanish (Mexico))", "Flo (Spanish (Mexico))"]}


def say(voice: str, text: str, name: str) -> None:
    subprocess.run(["say", "-v", voice, "-o", str(HERE / "clips" / name), "--file-format=WAVE",
                    "--data-format=LEF32@16000", text], check=True)


def clips() -> None:
    (HERE / "clips").mkdir(exist_ok=True)
    references = {}
    for language, texts in (("en", ENGLISH), ("es", SPANISH)):
        for index, voice in enumerate(VOICES[language]):
            for number, text in enumerate(texts):
                name = f"{language}-{'ab'[index]}-{number}.wav"
                say(voice, text, name)
                references[name] = text
        pause = f"{language}-pause.wav"
        say(VOICES[language][0], f"{texts[0]} [[slnc 1500]] {texts[3]}", pause)
        references[pause] = f"{texts[0]} {texts[3]}"
    (HERE / "refs.json").write_text(json.dumps(references, ensure_ascii=False, indent=1))


def build(name: str) -> None:
    (HERE / "Package.resolved").unlink(missing_ok=True)
    subprocess.run(["swift", "build", "-c", "release", "--product", "fluid-bench", "--scratch-path", f".build-{name}"],
                   cwd=HERE, env={**os.environ, "BENCH_FLUID": name}, check=True)


def binary(name: str) -> str:
    return str(HERE / f".build-{name}/release/fluid-bench")


def main(rounds: int) -> None:
    for target in ("SpeechCore", "LiveSpeech"):
        shutil.rmtree(HERE / "Sources" / target, ignore_errors=True)
        shutil.copytree(ROOT / "Sources" / target, HERE / "Sources" / target)
    clips()
    for name in ("fork", "upstream"):
        build(name)
    store = str(HERE / "store")
    subprocess.run([binary("upstream"), "install", store], check=True)
    results = HERE / "results"
    results.mkdir(exist_ok=True)
    for round_ in range(1, rounds + 1):
        order = ["fork", "upstream"] if round_ % 2 else ["upstream", "fork"]
        for checkpoint in ("v3", "ultra"):
            for name in order:
                subprocess.run([binary(name), "run", store, checkpoint, str(HERE / "clips"),
                                str(results / f"{name}-{checkpoint}-unpaced-{round_:02d}.json"), "unpaced"],
                               check=True, timeout=900)
    for round_ in range(1, 4):
        order = ["fork", "upstream"] if round_ % 2 else ["upstream", "fork"]
        for checkpoint in ("v3", "ultra"):
            for name in order:
                for prefix in ("en-a", "es-a"):
                    subprocess.run([binary(name), "run", store, checkpoint, str(HERE / "clips"),
                                    str(results / f"{name}-{checkpoint}-paced-{prefix}-{round_}.json"), "paced", prefix],
                                   check=True, timeout=900)
    for name in ("fork", "upstream"):
        output = subprocess.run([binary(name), "silero", store, str(HERE / "clips")],
                                check=True, capture_output=True, text=True).stdout
        (results / f"{name}-silero.txt").write_text(output)


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 15)
