/** WebAudio приём удалённого голоса с локальным gain (мьют / затухание). */

interface PeerAudioNodes {
  gain: GainNode;
  source: MediaStreamAudioSourceNode;
}

const peerAudio = new Map<string, PeerAudioNodes>();

export function attachRemoteAudio(
  ctx: AudioContext,
  peerId: string,
  stream: MediaStream,
  destination: AudioNode,
): GainNode {
  const existing = peerAudio.get(peerId);
  if (existing) return existing.gain;

  const source = ctx.createMediaStreamSource(stream);
  const gain = ctx.createGain();
  source.connect(gain);
  gain.connect(destination);
  peerAudio.set(peerId, { gain, source });
  return gain;
}

export function setPeerMuted(peerId: string, muted: boolean): void {
  const nodes = peerAudio.get(peerId);
  if (nodes) nodes.gain.gain.value = muted ? 0 : 1;
}

export function setPeerDistanceGain(
  peerId: string,
  distance: number,
  maxDist = 500,
): void {
  const nodes = peerAudio.get(peerId);
  if (!nodes) return;
  const d = Math.max(1, distance);
  const falloff = Math.min(1, (maxDist / d) ** 2);
  nodes.gain.gain.value = falloff;
}

export function disposePeerAudio(peerId: string): void {
  const nodes = peerAudio.get(peerId);
  if (!nodes) return;
  try {
    nodes.source.disconnect();
    nodes.gain.disconnect();
  } catch {
    // already disconnected
  }
  peerAudio.delete(peerId);
}

export function disposeAllPeerAudio(): void {
  for (const id of [...peerAudio.keys()]) disposePeerAudio(id);
}
