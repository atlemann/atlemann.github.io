with import <nixpkgs> {};
stdenv.mkDerivation {
  name = "env";
  buildInputs = [
    ruby.devEnv
    jekyll
    rubyPackages.jekyll
    rubyPackages_3_1.jekyll
  ];
}