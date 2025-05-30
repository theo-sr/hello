#!/bin/bash
# À configurer :
DIST="bookworm"
YOUR_GPG_KEY_ID="7B0473B658D17E35" # Ton ID de clé GPG
REPO_ROOT=$(pwd) # S'assure qu'on est à la racine du repo git

echo "Updating repository for $DIST (arm64 only)..."
echo "Using GPG Key ID: $YOUR_GPG_KEY_ID"

# Vérifier qu'il y a des packages .deb dans pool/main/
if [ -z "$(find $REPO_ROOT/pool/main -name '*.deb' -print -quit)" ]; then
    echo "Error: No .deb files found in $REPO_ROOT/pool/main/"
    exit 1
fi

# Créer la structure de répertoires nécessaire pour arm64
mkdir -p $REPO_ROOT/dists/$DIST/main/binary-arm64

# Générer le fichier Packages pour arm64
echo "Generating Packages file for arm64..."
dpkg-scanpackages $REPO_ROOT/pool/main /dev/null > $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages
# Note : dpkg-scanpackages va lister tous les paquets de pool/main.
# APT sur le client arm64 filtrera pour ne prendre que les paquets 'arm64' ou 'all'.

# Compresser le fichier Packages pour arm64
echo "Compressing Packages file for arm64..."
gzip -k -f $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages

# Définir les chemins pour les fichiers Release
RELEASE_FILE=$REPO_ROOT/dists/$DIST/Release
INRELEASE_FILE=$REPO_ROOT/dists/$DIST/InRelease
RELEASE_GPG_FILE=$REPO_ROOT/dists/$DIST/Release.gpg

# Créer le contenu de base du fichier Release
echo "Creating Release file..."
cat > $RELEASE_FILE << EOF
Origin: Mon Depot APT Personnalise
Label: Mon Depot
Suite: $DIST
Codename: $DIST
Components: main
Architectures: arm64
Date: $(date -Ru)
EOF

# Calculer et ajouter les checksums au fichier Release
# Le find doit chercher les fichiers Packages DANS la structure 'main/binary-arm64/'
echo "Generating checksums for Release file..."
(
    cd $REPO_ROOT/dists/$DIST || exit 1 # Se place dans dists/bookworm
    {
        echo "MD5Sum:"
        # Cherche Packages et Packages.gz dans main/binary-arm64/
        find main/binary-arm64 -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(md5sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done

        echo "SHA1:"
        find main/binary-arm64 -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(sha1sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done

        echo "SHA256:"
        find main/binary-arm64 -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(sha256sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done
    } >> $RELEASE_FILE # Ajoute les checksums au fichier Release
)

# Signer le fichier Release
echo "Signing the Release file..."
if [ -z "$YOUR_GPG_KEY_ID" ]; then
    echo "Error: YOUR_GPG_KEY_ID is not set in the script. Cannot sign the repository."
    exit 1
fi

# Créer InRelease (Release signé en clair)
gpg --batch --yes --default-key "$YOUR_GPG_KEY_ID" --clearsign -o $INRELEASE_FILE $RELEASE_FILE

# Créer Release.gpg (signature détachée)
gpg --batch --yes --default-key "$YOUR_GPG_KEY_ID" -abs -o $RELEASE_GPG_FILE $RELEASE_FILE

cd $REPO_ROOT # Retourner au répertoire racine initial

echo "Repository updated and signed successfully for arm64!"
echo "Packages found and listed in dists/$DIST/main/binary-arm64/Packages:"
# Affiche les noms des paquets listés pour arm64
grep "^Package:" $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages || echo " (No packages found or Packages file empty)"

echo ""
echo "N'oubliez pas d'ajouter votre clé publique GPG 'votre-cle-publique.asc' au dépôt si ce n'est pas fait."
echo "Et de commiter & pusher les changements :"
echo "  git add ."
echo "  git commit -m \"Update APT repository for $DIST (arm64) - $(date)\""
echo "  git push"
