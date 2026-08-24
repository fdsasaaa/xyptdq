<?php
/**
 * Website-side acceptance gate for Title SEO metadata produced by caipiaowenzhang.
 *
 * Responsibilities are intentionally narrow:
 * - preserve backward compatibility for historical packages;
 * - fail closed for packages that declare Title SEO V1.0;
 * - protect site-wide keyword ownership defined by content/keyword_map.json;
 * - reject unsupported Title SEO gate metadata before website Draft intake.
 *
 * This library never writes CMS, Draft, Scheduled, Publisher, Sitemap, or article state.
 */
declare(strict_types=1);

function xyptdq_title_seo_normalize(string $value): string
{
    $value = preg_replace('/[\s\-—_·•，。；;：:、\/\\|（）()【】\[\]《》<>“”‘’\'"!?！？]+/u', '', trim($value));
    return mb_strtolower((string) $value, 'UTF-8');
}

function xyptdq_title_seo_read_json(string $path, string $label): array
{
    if (!is_file($path)) {
        throw new RuntimeException($label . ' file not found: ' . $path);
    }
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data) || json_last_error() !== JSON_ERROR_NONE) {
        throw new RuntimeException($label . ' is invalid JSON: ' . json_last_error_msg());
    }
    return $data;
}

function xyptdq_title_seo_contract_declared(array $package): bool
{
    foreach (['title_seo_contract_version', 'title_candidates', 'title_selection_reason', 'title_review'] as $field) {
        if (array_key_exists($field, $package)) {
            return true;
        }
    }
    return false;
}

function xyptdq_title_seo_reserved_keywords(array $keywordMap): array
{
    $owners = [];
    foreach (($keywordMap['clusters'] ?? []) as $cluster) {
        if (!is_array($cluster)) {
            continue;
        }
        foreach (($cluster['keywords'] ?? []) as $row) {
            if (!is_array($row)) {
                continue;
            }
            $keyword = trim((string) ($row['keyword'] ?? ''));
            if ($keyword === '') {
                continue;
            }
            $normalized = xyptdq_title_seo_normalize($keyword);
            if ($normalized === '') {
                continue;
            }
            $owners[$normalized] = [
                'keyword' => $keyword,
                'target' => (string) ($row['target'] ?? ''),
                'cluster_id' => (string) ($cluster['id'] ?? ''),
                'cluster_name' => (string) ($cluster['name'] ?? ''),
            ];
        }
    }
    return $owners;
}

function xyptdq_title_seo_sensitive_claims(array $keywordMap): array
{
    $claims = [];
    foreach (($keywordMap['sensitive_intent_keywords'] ?? []) as $row) {
        if (!is_array($row)) {
            continue;
        }
        foreach (($row['prohibited_claims'] ?? []) as $claim) {
            $claim = trim((string) $claim);
            if ($claim !== '') {
                $claims[$claim] = true;
            }
        }
    }
    return array_keys($claims);
}

function xyptdq_title_seo_claim_is_critical(string $title): bool
{
    if (strpos($title, '？') !== false || strpos($title, '?') !== false) {
        return true;
    }
    foreach (['不', '并非', '不是', '不能', '风险', '警惕', '误区', '质疑', '可信吗', '可能吗'] as $token) {
        if (strpos($title, $token) !== false) {
            return true;
        }
    }
    return false;
}

function xyptdq_validate_title_seo_site_acceptance(array $package, ?string $repoRoot = null): array
{
    $repoRoot = $repoRoot ?? dirname(__DIR__, 3);
    $policy = xyptdq_title_seo_read_json($repoRoot . '/config/title_seo_intake_policy.json', 'Title SEO intake policy');
    $keywordMapPath = $repoRoot . '/' . ltrim((string) ($policy['keyword_map_path'] ?? 'content/keyword_map.json'), '/');
    $keywordMap = xyptdq_title_seo_read_json($keywordMapPath, 'keyword map');

    $errors = [];
    $warnings = [];
    $declared = xyptdq_title_seo_contract_declared($package);
    $expectedVersion = (string) ($policy['contract_version'] ?? '1.0');

    if (!$declared) {
        if (($policy['legacy_packages_allowed'] ?? true) !== true) {
            $errors[] = 'legacy package without Title SEO contract is not allowed';
        }
        return [
            'passed' => count($errors) === 0,
            'applicable' => false,
            'contract_version' => null,
            'errors' => $errors,
            'warnings' => $warnings,
            'reserved_primary_keyword_conflict' => null,
            'required_gates_verified' => 0,
        ];
    }

    $version = trim((string) ($package['title_seo_contract_version'] ?? ''));
    if ($version !== $expectedVersion) {
        $errors[] = 'title_seo_contract_version must be ' . $expectedVersion;
    }

    $title = trim((string) ($package['title'] ?? ''));
    $seoTitle = trim((string) ($package['seo_title'] ?? ''));
    if (($policy['require_title_equals_seo_title'] ?? true) === true && ($title === '' || $seoTitle === '' || $title !== $seoTitle)) {
        $errors[] = 'title and seo_title must be the same selected final title';
    }

    $candidateMin = (int) ($policy['candidate_min'] ?? 3);
    $candidateMax = (int) ($policy['candidate_max'] ?? 5);
    $candidates = $package['title_candidates'] ?? null;
    $candidateValues = [];
    if (!is_array($candidates)) {
        $errors[] = 'title_candidates must be an array';
    } else {
        foreach ($candidates as $candidate) {
            if (!is_string($candidate) || trim($candidate) === '') {
                $errors[] = 'title_candidates must contain non-empty strings';
                continue;
            }
            $candidateValues[] = trim($candidate);
        }
        if (count($candidateValues) < $candidateMin || count($candidateValues) > $candidateMax) {
            $errors[] = 'title_candidates must contain ' . $candidateMin . '-' . $candidateMax . ' candidates';
        }
        if (count($candidateValues) !== count(array_unique($candidateValues))) {
            $errors[] = 'title_candidates must not contain duplicates';
        }
        if ($title !== '' && !in_array($title, $candidateValues, true)) {
            $errors[] = 'selected title must exist in title_candidates';
        }
    }

    if (trim((string) ($package['title_selection_reason'] ?? '')) === '') {
        $errors[] = 'title_selection_reason is required';
    }

    $review = $package['title_review'] ?? null;
    $requiredGates = array_values($policy['required_gates'] ?? []);
    $requiredGatesVerified = 0;
    if (!is_array($review)) {
        $errors[] = 'title_review must be an object';
    } else {
        if (($review['passed'] ?? null) !== true) {
            $errors[] = 'title_review.passed must be true';
        }
        if ((string) ($review['contract_version'] ?? '') !== $expectedVersion) {
            $errors[] = 'title_review.contract_version mismatch';
        }
        if (($policy['require_selected_title_matches_review'] ?? true) === true && (string) ($review['selected_title'] ?? '') !== $title) {
            $errors[] = 'title_review.selected_title must match title';
        }
        if (($policy['require_candidate_set_matches_review'] ?? true) === true) {
            $reviewCandidates = $review['candidates'] ?? null;
            if (!is_array($reviewCandidates) || array_values($reviewCandidates) !== array_values($candidateValues)) {
                $errors[] = 'title_review.candidates must match title_candidates';
            }
        }
        $gates = $review['gates'] ?? null;
        if (!is_array($gates)) {
            $errors[] = 'title_review.gates must be an object';
        } else {
            foreach ($requiredGates as $gateName) {
                if (!isset($gates[$gateName]) || !is_array($gates[$gateName])) {
                    $errors[] = 'title_review missing required gate: ' . $gateName;
                    continue;
                }
                if (($gates[$gateName]['passed'] ?? null) !== true) {
                    $errors[] = 'title_review gate must pass: ' . $gateName;
                    continue;
                }
                $requiredGatesVerified++;
            }
        }
    }

    $reserved = xyptdq_title_seo_reserved_keywords($keywordMap);
    $primaryKeyword = trim((string) ($package['primary_keyword'] ?? ''));
    $primaryNormalized = xyptdq_title_seo_normalize($primaryKeyword);
    $reservedConflict = $reserved[$primaryNormalized] ?? null;
    if (($policy['block_reserved_primary_keyword_conflict'] ?? true) === true && $reservedConflict !== null) {
        $errors[] = 'primary_keyword conflicts with reserved site target: ' . $reservedConflict['keyword'] . ' -> ' . $reservedConflict['target'];
    }

    $titleNormalized = xyptdq_title_seo_normalize($title);
    if (($policy['block_exact_reserved_title'] ?? true) === true && isset($reserved[$titleNormalized])) {
        $owner = $reserved[$titleNormalized];
        $errors[] = 'title exactly duplicates a reserved site keyword target: ' . $owner['keyword'] . ' -> ' . $owner['target'];
    }

    if (($policy['enforce_sensitive_title_claim_prohibitions'] ?? true) === true && !xyptdq_title_seo_claim_is_critical($title)) {
        foreach (xyptdq_title_seo_sensitive_claims($keywordMap) as $claim) {
            if (strpos($title, $claim) !== false) {
                $errors[] = 'title contains prohibited unqualified claim: ' . $claim;
            }
        }
    }

    return [
        'passed' => count($errors) === 0,
        'applicable' => true,
        'contract_version' => $version,
        'errors' => array_values(array_unique($errors)),
        'warnings' => array_values(array_unique($warnings)),
        'reserved_primary_keyword_conflict' => $reservedConflict,
        'required_gates_verified' => $requiredGatesVerified,
    ];
}
