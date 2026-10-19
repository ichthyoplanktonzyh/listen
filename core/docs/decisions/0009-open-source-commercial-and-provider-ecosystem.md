# ADR 0009: Open-source, Commercial, And Provider Ecosystem Strategy

- Status: Proposed
- Date: 2026-06-14

## Context

LLPlayerNext is expected to support both an open-source community edition and
commercial development. The project should remain useful to individuals and
independent contributors without allowing the core product to be silently
turned into a closed derivative without reciprocal obligations.

Speech, phonetic-analysis, dictionary, playback, and future learning providers
also have independent runtimes, model weights, training-data provenance,
licenses, and distribution restrictions. Binding the core product directly to
one provider or model license would constrain both the open-source and
commercial paths.

An OSI-approved open-source license cannot prohibit commercial use or exclude
large companies. Preventing all uncompensated commercial use is therefore not
compatible with calling the resulting license open source.

## Proposed Decision

Prepare LLPlayerNext for dual licensing:

- license the core application and official first-party advanced providers
  under `AGPL-3.0-only` for the open-source edition;
- offer a separate commercial license for organizations that cannot or do not
  want to comply with the AGPL terms;
- publish provider protocol schemas, SDKs, and minimal example providers under
  a permissive license such as `Apache-2.0`;
- manage the LLPlayerNext name, logo, and distribution identity under a
  separate trademark policy;
- license model weights, datasets, and third-party runtimes independently and
  never imply that the core license grants rights to those assets.

This is a proposed direction, not an immediate license grant. The repository
continues to grant no LLPlayerNext license until ownership, contributor terms,
the commercial license, trademark policy, dependency inventory, and legal
review are ready. ADR 0001 remains authoritative until this ADR is accepted and
the actual license files are added.

## Provider Boundary

Providers should use a versioned, capability-negotiated contract. The preferred
long-term execution boundary for third-party or commercially licensed providers
is an out-of-process adapter using local authenticated IPC or loopback HTTP.

The provider contract must:

- keep provider, runtime, model, and profile identities independent;
- preserve immutable runtime/model revision, checksum, provenance, and license
  snapshots on every job and analysis;
- expose normalized results rather than library-specific types or flags;
- negotiate optional capabilities and reject incompatible versions safely;
- allow providers to be installed, removed, or replaced without invalidating
  historical results;
- record whether code, runtime, model, and data licenses permit research,
  redistribution, and commercial use as separate decisions.

An out-of-process boundary improves operational isolation and makes it possible
to support permissive, copyleft, proprietary, local, and remote providers.
It does not by itself settle whether two components form one combined work
under copyright law; each distribution still requires legal review.

## Contributor And Distribution Requirements

Before accepting this ADR:

- choose a contributor agreement or copyright-assignment policy that permits
  continued dual licensing;
- obtain agreement from all copyright holders before relicensing existing
  contributions;
- prepare reviewed AGPL and commercial-license texts;
- prepare a trademark and official-build policy;
- automate dependency, runtime, model, and dataset license inventories;
- distinguish source availability from rights to signed builds, hosted
  services, enterprise support, and proprietary providers.

## Consequences

- Community users retain a real open-source edition with reciprocal source
  obligations.
- Closed-source embedding and modified hosted deployments become potential
  commercial-license use cases.
- Provider authors can implement the stable protocol without inheriting the
  core application's implementation details.
- Permissively licensed providers such as Vosk can be evaluated without making
  their license the license of LLPlayerNext.
- AGPL does not guarantee payment and cannot prohibit commercial use; the
  commercial offering must provide practical value beyond license avoidance.
- Contributor administration and legal review become ongoing project work.

## References

- [GNU Affero General Public License](https://www.gnu.org/licenses/agpl-3.0.html)
- [Open Source Definition](https://opensource.org/osd)
- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- [ADR 0001](./0001-repository-and-license.md)
- [ADR 0006](./0006-transcription-provider-and-models.md)
- [ADR 0008](./0008-m20-phase0-phonetic-provider-research.md)
