import asyncio
from struct import pack

from app import waveform


def test_pcm16le_to_peaks_returns_normalized_buckets():
    pcm = b"".join(
        pack("<h", value) for value in [0, 1000, -2000, 4000, -8000, 16000]
    )

    peaks = waveform.pcm16le_to_peaks(pcm, 3)

    assert len(peaks) == 3
    assert peaks == [0.062, 0.25, 1.0]
    assert all(0 <= peak <= 1 for peak in peaks)


def test_analyze_waveform_falls_back_when_decode_fails(monkeypatch):
    async def fail_decode(_stream_url, _request_headers):
        raise TimeoutError("too slow")

    monkeypatch.setattr(waveform, "_decode_pcm", fail_decode)

    peaks = asyncio.run(
        waveform.analyze_waveform_peaks("https://example.test/a.mp3", fallback=[0.2])
    )

    assert peaks == [0.2]


def test_analyze_waveform_falls_back_when_ffmpeg_returns_no_audio(monkeypatch):
    async def empty_decode(_stream_url, _request_headers):
        return b""

    monkeypatch.setattr(waveform, "_decode_pcm", empty_decode)

    peaks = asyncio.run(
        waveform.analyze_waveform_peaks("https://example.test/a.mp3", fallback=[0.3])
    )

    assert peaks == [0.3]
