# Fixture environment layer for the CI cache checks: only *.fixture.example
# values, shared by the contract check and the tool scenario check.
{
  nix = {
    readEndpoints = ["https://nix-cache.fixture.example"];
    protectedWriteEndpoint = "https://nix-upload.fixture.example";
    pullRequestWriteEndpoint = "s3://nix-quarantine-fixture?endpoint=https://objects.fixture.example";
    trustedPublicKeys = ["fixture-cache.example-1:PUBLIC-KEY-FIXTURE"];
  };

  rust = {
    endpoint = "https://objects.fixture.example";
    bucket = "fixture-compiler-cache";
    region = "fixture-1";
    keyPrefix = "ci/fixture";
  };

  python = {
    endpoint = "https://objects.fixture.example";
    bucket = "fixture-python-cache";
    region = "fixture-1";
    keyPrefix = "ci/fixture";
  };
}
