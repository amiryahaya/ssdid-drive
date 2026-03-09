using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddKemPublicKey : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "KemAlgorithm",
                table: "users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "KemPublicKey",
                table: "users",
                type: "bytea",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "KemAlgorithm",
                table: "users");

            migrationBuilder.DropColumn(
                name: "KemPublicKey",
                table: "users");
        }
    }
}
