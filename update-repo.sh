#!/bin/bash
# À configurer :
DIST="bookworm"
YOUR_GPG_KEY_ID="7B0473B658D17E35" # Remplace par ton ID de clé GPG
REPO_ROOT=$(pwd) # S'assure qu'on est à la racine du repo git

echo "Updating repository for $DIST..."
echo "Using GPG Key ID: $YOUR_GPG_KEY_ID"

# Vérifier qu'il y a des packages
if [ -z "$(find $REPO_ROOT/pool/main -name '*.deb' -print -quit)" ]; then
    echo "Error: No .deb files found in pool/main/"
    exit 1
fi

# Créer les répertoires
mkdir -p $REPO_ROOT/dists/$DIST/main/binary-{arm64}

# Générer les fichiers Packages
echo "Generating Packages files..."
# Note: dpkg-scanpackages -m pool/ ... est mieux si les .deb sont dans des sous-répertoires de pool/
# Pour une structure plate pool/main/monpaquet.deb :
dpkg-scanpackages pool/main /dev/null > $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages

# Compresser
echo "Compressing Packages files..."
gzip -k -f $REPO_ROOT/dists/$DIST/main/binary-arm64/Packages

# Créer le fichier Release
echo "Creating Release file..."
RELEASE_FILE=$REPO_ROOT/dists/$DIST/Release
INRELEASE_FILE=$REPO_ROOT/dists/$DIST/InRelease
RELEASE_GPG_FILE=$REPO_ROOT/dists/$DIST/Release.gpg

# Contenu de base du fichier Release
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
# Doit être exécuté depuis le répertoire dists/$DIST pour que les chemins soient relatifs
echo "Generating checksums for Release file..."
(
    cd $REPO_ROOT/dists/$DIST || exit 1 # Change de répertoire, quitte si échec
    {
        echo "MD5Sum:"
        find main -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(md5sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done

        echo "SHA1:"
        find main -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(sha1sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done

        echo "SHA256:"
        find main -name "Packages*" -type f | while read file; do
            size=$(stat -c%s "$file")
            hash=$(sha256sum "$file" | cut -d' ' -f1)
            printf " %s %8d %s\\n" "$hash" "$size" "$file"
        done
    } >> $RELEASE_FILE # Ajoute au fichier Release (qui est dans le répertoire parent maintenant)
)

# Signer le fichier Release
echo "Signing the Release file..."
if [ -z "$YOUR_GPG_KEY_ID" ]; then
    echo "Error: YOUR_GPG_KEY_ID is not set. Cannot sign the repository."
    exit 1
fi

# Créer InRelease (Release signé en clair)
gpg --default-key "$YOUR_GPG_KEY_ID" --clearsign -o $INRELEASE_FILE $RELEASE_FILE

# Créer Release.gpg (signature détachée)
gpg --default-key "$YOUR_GPG_KEY_ID" -abs -o $RELEASE_GPG_FILE $RELEASE_FILE

cd $REPO_ROOT # Retourner au répertoire racine initial

echo "Repository updated and signed successfully!"
echo "Packages found in binary-all:"
grep "^Package:" $REPO_ROOT/dists/$DIST/main/binary-all/Packages || echo " (No packages found or file empty)"

echo ""
echo "N'oubliez pas d'ajouter votre clé publique GPG 'votre-cle-publique.asc' au dépôt si ce n'est pas fait."
echo "Et de commiter & pusher les changements :"
echo "git add ."
echo "git commit -m \"Update APT repository - $(date)\""
echo "git push"
