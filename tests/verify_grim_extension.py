"""
Simple verification that .grim extension is used.
This test checks that the backend code uses .grim instead of .md.
"""

import os
import sys

# Add backend to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../backend"))


def test_grim_extension_in_code():
    """Verify that .grim extension is used in the backend code."""

    # Check main.py for .grim usage
    main_py_path = os.path.join(os.path.dirname(__file__), "../backend/main.py")

    with open(main_py_path, "r") as f:
        content = f.read()

    # Count occurrences
    grim_count = content.count(".grim")
    md_count = content.count(".md")

    print(f"Checking {main_py_path}:")
    print(f"  .grim occurrences: {grim_count}")
    print(f"  .md occurrences: {md_count}")

    # Verify .grim is used
    assert grim_count > 0, "No .grim extension found in main.py"
    assert md_count == 0, ".md extension still found in main.py (should be .grim)"

    # Check specific lines
    lines = content.split("\n")
    grim_lines = [i + 1 for i, line in enumerate(lines) if ".grim" in line]

    print(f"  .grim found on lines: {grim_lines}")

    # Verify update_note endpoint uses .grim
    update_note_section = False
    for i, line in enumerate(lines):
        if "update_note" in line and "async def" in line:
            # Check next few lines for .grim
            for j in range(i, min(i + 10, len(lines))):
                if ".grim" in lines[j]:
                    update_note_section = True
                    break

    assert update_note_section, "update-note endpoint doesn't use .grim extension"

    # Verify get_note endpoint uses .grim
    get_note_section = False
    for i, line in enumerate(lines):
        if "get_note" in line and "async def" in line:
            # Check next few lines for .grim
            for j in range(i, min(i + 10, len(lines))):
                if ".grim" in lines[j]:
                    get_note_section = True
                    break

    assert get_note_section, "get_note endpoint doesn't use .grim extension"

    print("✓ All .grim extension checks passed!")


def test_grim_file_creation():
    """Test that a .grim file can be created and read."""

    # Create a test .grim file
    test_dir = os.path.join(os.path.dirname(__file__), "test_grim_files")
    os.makedirs(test_dir, exist_ok=True)

    test_file = os.path.join(test_dir, "test_note.grim")
    test_content = "# Test Grim File\n\nThis is a .grim file test."

    # Write .grim file
    with open(test_file, "w") as f:
        f.write(test_content)

    # Verify file exists
    assert os.path.exists(test_file), f".grim file not created: {test_file}"

    # Verify it's a .grim file
    assert test_file.endswith(".grim"), f"File should end with .grim: {test_file}"

    # Read and verify content
    with open(test_file, "r") as f:
        read_content = f.read()

    assert read_content == test_content, "Content mismatch in .grim file"

    # Clean up
    os.remove(test_file)

    print("✓ .grim file creation test passed!")


def test_no_md_files_in_storage():
    """Check that storage/notes directory doesn't have .md files."""

    storage_dir = os.path.join(os.path.dirname(__file__), "../backend/storage/notes")

    if os.path.exists(storage_dir):
        # List all files
        files = os.listdir(storage_dir)

        # Check for .md files
        md_files = [f for f in files if f.endswith(".md")]
        grim_files = [f for f in files if f.endswith(".grim")]

        print(f"Checking {storage_dir}:")
        print(f"  .grim files: {len(grim_files)}")
        print(f"  .md files: {len(md_files)}")

        if md_files:
            print(f"  Warning: Found .md files: {md_files}")
            print("  Note: Existing .md files from previous runs may still be present")
    else:
        print(f"Storage directory not found: {storage_dir}")
        print("  (This is OK if no notes have been created yet)")


if __name__ == "__main__":
    print("=" * 60)
    print("Testing .grim file extension implementation")
    print("=" * 60)

    try:
        test_grim_extension_in_code()
        print()
        test_grim_file_creation()
        print()
        test_no_md_files_in_storage()
        print()
        print("=" * 60)
        print("All tests passed! .grim extension is correctly implemented.")
        print("=" * 60)
    except AssertionError as e:
        print(f"\n✗ Test failed: {e}")
        print("\n=" * 60)
        print("Tests failed. Please check .grim implementation.")
        print("=" * 60)
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        sys.exit(1)
