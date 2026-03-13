using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddE2eeFieldsToFoldersAndFiles : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "EncryptedMetadata",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "KemCiphertext",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "MetadataNonce",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "MlKemCiphertext",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OwnerKemCiphertext",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OwnerMlKemCiphertext",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "OwnerWrappedKek",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Signature",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "WrappedKek",
                table: "folders",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "BlobHash",
                table: "files",
                type: "character varying(128)",
                maxLength: 128,
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "BlobSize",
                table: "files",
                type: "bigint",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "ChunkCount",
                table: "files",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "EncryptedMetadata",
                table: "files",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "KemCiphertext",
                table: "files",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "MlKemCiphertext",
                table: "files",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Signature",
                table: "files",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Status",
                table: "files",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "complete");

            migrationBuilder.AddColumn<string>(
                name: "WrappedDek",
                table: "files",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "EncryptedMetadata",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "KemCiphertext",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "MetadataNonce",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "MlKemCiphertext",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "OwnerKemCiphertext",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "OwnerMlKemCiphertext",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "OwnerWrappedKek",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "Signature",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "WrappedKek",
                table: "folders");

            migrationBuilder.DropColumn(
                name: "BlobHash",
                table: "files");

            migrationBuilder.DropColumn(
                name: "BlobSize",
                table: "files");

            migrationBuilder.DropColumn(
                name: "ChunkCount",
                table: "files");

            migrationBuilder.DropColumn(
                name: "EncryptedMetadata",
                table: "files");

            migrationBuilder.DropColumn(
                name: "KemCiphertext",
                table: "files");

            migrationBuilder.DropColumn(
                name: "MlKemCiphertext",
                table: "files");

            migrationBuilder.DropColumn(
                name: "Signature",
                table: "files");

            migrationBuilder.DropColumn(
                name: "Status",
                table: "files");

            migrationBuilder.DropColumn(
                name: "WrappedDek",
                table: "files");
        }
    }
}
