using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddInvitationShortCode : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ShortCode",
                table: "invitations",
                type: "character varying(16)",
                maxLength: 16,
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateIndex(
                name: "IX_invitations_ShortCode",
                table: "invitations",
                column: "ShortCode",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_invitations_ShortCode",
                table: "invitations");

            migrationBuilder.DropColumn(
                name: "ShortCode",
                table: "invitations");
        }
    }
}
