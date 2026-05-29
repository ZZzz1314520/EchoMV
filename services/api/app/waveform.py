from __future__ import annotations

import asyncio
from array import array
import math
import sys

from .config import settings


MAX_ANALYSIS_SECONDS = 300
SAMPLE_RATE = 8000


async def analyze_waveform_peaks(
    stream_url: str,
    request_headers: dict[str, str] | None = None,
    fallback: list[float] | None = None,
) -> list[float] | None:
    try:
        pcm = await _decode_pcm(stream_url, request_headers or {})
        peaks = pcm16le_to_peaks(pcm, settings.waveform_buckets)
        return peaks or fallback
    except Exception:
        return fallback


async def _decode_pcm(stream_url: str, request_headers: dict[str, str]) -> bytes:
    ffmpeg = _ffmpeg_path()
    args = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
    ]
    if request_headers:
        args.extend(["-headers", _format_headers(request_headers)])
    args.extend(
        [
            "-i",
            stream_url,
            "-t",
            str(MAX_ANALYSIS_SECONDS),
            "-vn",
            "-ac",
            "1",
            "-ar",
            str(SAMPLE_RATE),
            "-f",
            "s16le",
            "pipe:1",
        ]
    )

    process = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(
            process.communicate(),
            timeout=settings.waveform_timeout_seconds,
        )
    except asyncio.TimeoutError:
        process.kill()
        await process.communicate()
        raise

    if process.returncode != 0:
        raise RuntimeError(stderr.decode("utf-8", errors="ignore") or "ffmpeg failed")
    return stdout


def _ffmpeg_path() -> str:
    if settings.ffmpeg_path:
        return settings.ffmpeg_path

    try:
        import imageio_ffmpeg
    except Exception as error:
        raise RuntimeError("imageio-ffmpeg is unavailable") from error
    return imageio_ffmpeg.get_ffmpeg_exe()


def _format_headers(headers: dict[str, str]) -> str:
    return "".join(f"{key}: {value}\r\n" for key, value in headers.items())


def pcm16le_to_peaks(data: bytes, buckets: int) -> list[float]:
    if not data or buckets <= 0:
        return []

    usable = data[: len(data) - (len(data) % 2)]
    samples = array("h")
    samples.frombytes(usable)
    if sys.byteorder != "little":
        samples.byteswap()
    if not samples:
        return []

    bucket_size = max(1, math.ceil(len(samples) / buckets))
    raw_peaks: list[float] = []
    for bucket_index in range(buckets):
        start = bucket_index * bucket_size
        end = min(len(samples), start + bucket_size)
        if start >= len(samples):
            raw_peaks.append(0)
            continue
        raw_peaks.append(max(abs(sample) for sample in samples[start:end]) / 32768)

    loudest = max(raw_peaks)
    if loudest <= 0:
        return [0 for _ in range(buckets)]
    return [round(min(1.0, peak / loudest), 3) for peak in raw_peaks]
