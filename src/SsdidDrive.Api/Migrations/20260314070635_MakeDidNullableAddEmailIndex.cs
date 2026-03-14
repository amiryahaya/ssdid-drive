using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class MakeDidNullableAddEmailIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_users_Did",
                table: "users");

            migrationBuilder.AlterColumn<string>(
                name: "Did",
                table: "users",
                type: "character varying(256)",
                maxLength: 256,
                nullable: true,
                oldClrType: typeof(string),
                oldType: "character varying(256)",
                oldMaxLength: 256);

            migrationBuilder.AddColumn<Guid>(
                name: "AcceptedByAccountId",
                table: "invitations",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_users_Did",
                table: "users",
                column: "Did",
                unique: true,
                filter: "\"Did\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_users_Email",
                table: "users",
                column: "Email",
                unique: true,
                filter: "\"Email\" IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_users_Did",
                table: "users");

            migrationBuilder.DropIndex(
                name: "IX_users_Email",
                table: "users");

            migrationBuilder.DropColumn(
                name: "AcceptedByAccountId",
                table: "invitations");

            migrationBuilder.AlterColumn<string>(
                name: "Did",
                table: "users",
                type: "character varying(256)",
                maxLength: 256,
                nullable: false,
                defaultValue: "",
                oldClrType: typeof(string),
                oldType: "character varying(256)",
                oldMaxLength: 256,
                oldNullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_users_Did",
                table: "users",
                column: "Did",
                unique: true);
        }
    }
}
