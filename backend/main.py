"""
KSRTC Benchmarking Backend — Feature Validation Server

Provides endpoints to cross-validate mobile-computed features
against Python (NumPy/SciPy) reference implementations.

Run: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
"""

from fastapi import FastAPI
from pydantic import BaseModel
import numpy as np
from scipy.fft import fft as scipy_fft
from typing import List, Dict

app = FastAPI(
    title="KSRTC Feature Validation API",
    version="1.0.0",
)


# ═══════════════════════════════════════════════════════════════════
# Request/Response Models
# ═══════════════════════════════════════════════════════════════════


class FeatureRequest(BaseModel):
    """Raw signal array for a single attribute in a segment."""
    signal: List[float]
    attribute_name: str
    sampling_rate: float = 10.0


class FeatureResponse(BaseModel):
    """All 15 features computed for the signal."""
    attribute_name: str
    features: Dict[str, float]


class SegmentRequest(BaseModel):
    """All 8 attribute signals for one segment."""
    speed: List[float]
    ay: List[float]
    ax: List[float]
    yr: List[float]
    jx: List[float]
    jy: List[float]
    vv: List[float]
    r: List[float]
    sampling_rate: float = 10.0


class SegmentResponse(BaseModel):
    """120 features for the segment."""
    features: Dict[str, float]
    total_count: int


class DeviationRequest(BaseModel):
    """Features + benchmark ranges for deviation computation."""
    feature_values: Dict[str, float]
    terrain: str


class DeviationResponse(BaseModel):
    cluster0_deviation: float
    cluster1_deviation: float
    matched_cluster: int


class CompareRequest(BaseModel):
    """Compare mobile vs Python features."""
    mobile_features: Dict[str, float]
    signal: List[float]
    attribute_name: str
    tolerance_pct: float = 2.0


class CompareResponse(BaseModel):
    mismatches: List[Dict[str, float]]
    all_match: bool


# ═══════════════════════════════════════════════════════════════════
# Feature Computation (Reference Implementation)
# ═══════════════════════════════════════════════════════════════════


def compute_time_domain(signal: np.ndarray) -> Dict[str, float]:
    """Compute 11 time-domain features using NumPy."""
    n = len(signal)
    if n == 0:
        return {k: 0.0 for k in [
            "Max", "Min", "Mean", "Std", "PeakToPeak",
            "ARV", "RMS", "ShapeFactor", "CrestFactor",
            "ImpulseFactor", "MarginFactor"
        ]}

    max_val = float(np.max(signal))
    min_val = float(np.min(signal))
    mean_val = float(np.mean(signal))
    std_val = float(np.std(signal, ddof=1)) if n > 1 else 0.0
    peak_to_peak = max_val - min_val
    arv = float(np.mean(np.abs(signal)))
    rms = float(np.sqrt(np.mean(signal ** 2)))

    eps = 1e-12
    shape_factor = rms / arv if arv > eps else 0.0
    crest_factor = max_val / rms if rms > eps else 0.0
    impulse_factor = max_val / arv if arv > eps else 0.0

    mean_sqrt_abs = float(np.mean(np.sqrt(np.abs(signal))))
    margin_denom = mean_sqrt_abs ** 2
    margin_factor = max_val / margin_denom if margin_denom > eps else 0.0

    return {
        "Max": max_val,
        "Min": min_val,
        "Mean": mean_val,
        "Std": std_val,
        "PeakToPeak": peak_to_peak,
        "ARV": arv,
        "RMS": rms,
        "ShapeFactor": shape_factor,
        "CrestFactor": crest_factor,
        "ImpulseFactor": impulse_factor,
        "MarginFactor": margin_factor,
    }


def compute_frequency_domain(
    signal: np.ndarray, fs: float = 10.0
) -> Dict[str, float]:
    """Compute 4 frequency-domain features using SciPy FFT."""
    n = len(signal)
    if n < 2:
        return {k: 0.0 for k in [
            "AvgAmplitude", "FreqCentroid", "FreqVariance", "SpectralEntropy"
        ]}

    # FFT
    X = scipy_fft(signal)
    half_n = n // 2
    magnitudes = np.abs(X[:half_n])
    frequencies = np.arange(half_n) * fs / n

    sum_mag = np.sum(magnitudes)
    eps = 1e-12

    # Average Amplitude
    avg_amplitude = float(np.mean(magnitudes))

    # Frequency Centroid
    freq_centroid = (
        float(np.sum(frequencies * magnitudes) / sum_mag)
        if sum_mag > eps else 0.0
    )

    # Frequency Variance
    freq_variance = (
        float(np.sum((frequencies - freq_centroid) ** 2 * magnitudes) / sum_mag)
        if sum_mag > eps else 0.0
    )

    # Spectral Entropy
    spectral_entropy = 0.0
    if sum_mag > eps:
        pk = magnitudes / sum_mag
        pk = pk[pk > eps]
        spectral_entropy = float(-np.sum(pk * np.log2(pk)))

    return {
        "AvgAmplitude": avg_amplitude,
        "FreqCentroid": freq_centroid,
        "FreqVariance": freq_variance,
        "SpectralEntropy": spectral_entropy,
    }


def compute_all_features(
    signal: np.ndarray, fs: float = 10.0
) -> Dict[str, float]:
    """Compute all 15 features for a signal."""
    td = compute_time_domain(signal)
    fd = compute_frequency_domain(signal, fs)
    td.update(fd)
    return td


# ═══════════════════════════════════════════════════════════════════
# API Endpoints
# ═══════════════════════════════════════════════════════════════════


@app.post("/validate-features", response_model=FeatureResponse)
async def validate_features(req: FeatureRequest):
    """Compute all 15 features for a single attribute signal."""
    signal = np.array(req.signal, dtype=np.float64)
    features = compute_all_features(signal, req.sampling_rate)
    return FeatureResponse(
        attribute_name=req.attribute_name,
        features=features,
    )


@app.post("/validate-segment", response_model=SegmentResponse)
async def validate_segment(req: SegmentRequest):
    """Compute all 120 features for a complete segment."""
    attributes = {
        "Speed": np.array(req.speed),
        "ay": np.array(req.ay),
        "ax": np.array(req.ax),
        "YR": np.array(req.yr),
        "Jx": np.array(req.jx),
        "Jy": np.array(req.jy),
        "VV": np.array(req.vv),
        "R": np.array(req.r),
    }

    all_features = {}
    for name, signal in attributes.items():
        features = compute_all_features(signal, req.sampling_rate)
        for feat_name, value in features.items():
            all_features[f"{name}_{feat_name}"] = value

    return SegmentResponse(
        features=all_features,
        total_count=len(all_features),
    )


@app.post("/compare-features", response_model=CompareResponse)
async def compare_features(req: CompareRequest):
    """Compare mobile-computed features against Python reference."""
    signal = np.array(req.signal, dtype=np.float64)
    ref_features = compute_all_features(signal)

    mismatches = []
    for feat_name, ref_val in ref_features.items():
        key = f"{req.attribute_name}_{feat_name}"
        mobile_val = req.mobile_features.get(key)
        if mobile_val is None:
            continue

        if abs(ref_val) < 1e-10:
            pct_diff = abs(mobile_val) * 100
        else:
            pct_diff = abs(mobile_val - ref_val) / abs(ref_val) * 100

        if pct_diff > req.tolerance_pct:
            mismatches.append({
                "feature": feat_name,
                "mobile_value": mobile_val,
                "python_value": ref_val,
                "pct_difference": round(pct_diff, 4),
            })

    return CompareResponse(
        mismatches=mismatches,
        all_match=len(mismatches) == 0,
    )


@app.get("/health")
async def health():
    return {"status": "ok", "service": "ksrtc-validation"}
